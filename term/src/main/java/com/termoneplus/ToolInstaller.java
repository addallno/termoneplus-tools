/*
 * 工具安装与 SSH 服务管理（Termux 风格目录布局）
 *
 * 目录结构（对齐 Termux）：
 *   $PREFIX = /data/data/<包名>/files/usr
 *   $HOME   = /data/data/<包名>/files/home
 *   $PREFIX/bin  = 工具二进制（dropbear/busybox 及其符号链接）
 *   登录 shell = /system/bin/sh
 *   authorized_keys = $HOME/.ssh/authorized_keys
 */

package com.termoneplus;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;

public class ToolInstaller {

    private static final String TAG = "ToolInstaller";

    public static final String CONFIG_FILE_NAME = "termtools.conf";
    public static final int DEFAULT_SSH_PORT = 8023;

    /* ---- 目录布局 ---- */

    public static File getPrefix(Context ctx) {
        return new File(ctx.getFilesDir(), "usr");
    }

    public static File getHomeDir(Context ctx) {
        return new File(ctx.getFilesDir(), "home");
    }

    public static File getBinDir(Context ctx) {
        return new File(getPrefix(ctx), "bin");
    }

    public static File getDropbearEtcDir(Context ctx) {
        return new File(getPrefix(ctx), "etc/dropbear");
    }

    public static File getHostKeyFile(Context ctx) {
        return new File(getDropbearEtcDir(ctx), "dropbear_host_key");
    }

    public static File getPidFile(Context ctx) {
        return new File(getDropbearEtcDir(ctx), "dropbear.pid");
    }

    public static File getStartScript(Context ctx) {
        return new File(getBinDir(ctx), "start_ssh.sh");
    }

    public static File getBusybox(Context ctx) {
        return new File(getBinDir(ctx), "busybox");
    }

    public static File getDropbear(Context ctx) {
        return new File(getBinDir(ctx), "dropbear");
    }

    public static File getConfigFile(Context ctx) {
        return new File(getPrefix(ctx), "etc/termtools.conf");
    }

    /* ---- 配置读写 ---- */

    /** 读取 termtools.conf 中的 KEY=VALUE（# 注释，忽略空行） */
    private static String getConfig(Context ctx, String key, String def) {
        File conf = getConfigFile(ctx);
        if (conf.exists()) {
            try {
                for (String line : new String(readAll(conf), "UTF-8").split("\n")) {
                    line = line.trim();
                    if (line.isEmpty() || line.startsWith("#"))
                        continue;
                    int eq = line.indexOf('=');
                    if (eq > 0 && line.substring(0, eq).trim().equals(key))
                        return line.substring(eq + 1).trim();
                }
            } catch (IOException ignored) {
            }
        }
        return def;
    }

    public static int getSshPort(Context ctx) {
        String v = getConfig(ctx, "SSH_PORT", String.valueOf(DEFAULT_SSH_PORT));
        try {
            return Integer.parseInt(v);
        } catch (NumberFormatException e) {
            return DEFAULT_SSH_PORT;
        }
    }

    public static boolean isAutoStartSsh(Context ctx) {
        String v = getConfig(ctx, "AUTO_START_SSH", "1");
        return v.equals("1") || v.equalsIgnoreCase("yes") || v.equalsIgnoreCase("true");
    }

    /** 首次安装写入默认配置（已存在则保留用户修改） */
    private static void ensureConfigFile(Context ctx) throws IOException {
        File conf = getConfigFile(ctx);
        if (conf.exists())
            return;
        ensureDir(conf.getParentFile());
        String content = "# TermTools 配置文件（KEY=VALUE，行首 # 为注释）\n"
                + "# SSH 服务监听端口\n"
                + "SSH_PORT=" + DEFAULT_SSH_PORT + "\n"
                + "# 打开 app 时是否自动启动 SSH 服务（1=启动, 0=不启动）\n"
                + "AUTO_START_SSH=1\n";
        OutputStream os = new FileOutputStream(conf);
        os.write(content.getBytes("UTF-8"));
        os.close();
    }

    private static byte[] readAll(File f) throws IOException {
        InputStream is = new java.io.FileInputStream(f);
        java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = is.read(buf)) > 0)
            bos.write(buf, 0, n);
        is.close();
        return bos.toByteArray();
    }

    /* ---- 安装流程（幂等）---- */

    public static boolean install(final Context ctx) {
        try {
            File home = getHomeDir(ctx);
            File bin = getBinDir(ctx);
            File etc = getDropbearEtcDir(ctx);

            ensureDir(home);
            ensureDir(bin);
            ensureDir(etc);

            // 0) 默认配置文件（首次生成，已存在保留用户修改）
            ensureConfigFile(ctx);

            // 1) busybox --install -s 生成 applet 符号链接（先装，避免覆盖资产的完整工具）
            File busybox = getBusybox(ctx);
            if (busybox.exists()) {
                java.lang.Process p = new ProcessBuilder(busybox.getAbsolutePath(),
                        "--install", "-s", bin.getAbsolutePath())
                        .redirectErrorStream(true).start();
                p.waitFor();
            }

            // 2) 解压 assets/tools（usr 目录树）→ $PREFIX。
            //    放在 busybox --install 之后：assets 里的完整工具（unzip/ping/tree/
            //    hexdump/openssl/rsync/traceroute/strings/file 等是 busybox 同名 applet，
            //    会被符号链接覆盖）以真实文件覆盖回符号链接，保证完整版优先。
            extractTools(ctx.getAssets(), getPrefix(ctx));

            // 3) authorized_keys → $HOME/.ssh/authorized_keys
            File auth = new File(new File(home, ".ssh"), "authorized_keys");
            if (!auth.exists()) {
                ensureDir(new File(home, ".ssh"));
                copyAsset(ctx.getAssets(), "ssh/authorized_keys", auth);
                auth.setReadable(true, true);
                auth.setWritable(true, true);
                auth.setExecutable(false);
            }

            // 4) 写 start_ssh.sh 并加执行位
            writeStartScript(ctx);

            // 5) 按配置决定是否启动 dropbear
            if (isAutoStartSsh(ctx)) {
                java.lang.Process p = new ProcessBuilder("/system/bin/sh", getStartScript(ctx).getAbsolutePath())
                        .redirectErrorStream(true).start();
                // 不等待：dropbear 自行 daemonize 后台常驻
                Log.i(TAG, "ssh service started on port " + getSshPort(ctx));
            } else {
                Log.i(TAG, "AUTO_START_SSH=0, 跳过启动 SSH");
            }
            return true;
        } catch (Exception e) {
            Log.e(TAG, "install failed", e);
            return false;
        }
    }

    /* ---- start_ssh.sh ---- */

    private static void writeStartScript(Context ctx) throws IOException {
        File script = getStartScript(ctx);

        String home = getHomeDir(ctx).getAbsolutePath();
        String prefix = getPrefix(ctx).getAbsolutePath();
        String hostkey = getHostKeyFile(ctx).getAbsolutePath();
        String pidfile = getPidFile(ctx).getAbsolutePath();
        String dropbear = getDropbear(ctx).getAbsolutePath();
        String dropbearkey = new File(getBinDir(ctx), "dropbearkey").getAbsolutePath();
        int port = getSshPort(ctx);

        StringBuilder sb = new StringBuilder();
        sb.append("#!/system/bin/sh\n");
        sb.append("# 启动/重启 dropbear SSH 服务（幂等）。端口取自 ").append(getConfigFile(ctx).getAbsolutePath()).append("\n");
        sb.append("export HOME=").append(home).append("\n");
        sb.append("export PREFIX=").append(prefix).append("\n");
        sb.append("export PATH=$PREFIX/bin:/system/bin:/system/xbin:$HOME:$HOME/cmd:$PATH\n");
        sb.append("export USER=root\n");
        sb.append("export SHELL=/system/bin/sh\n");
        sb.append("\n");
        sb.append("ETC=$PREFIX/etc/dropbear\n");
        sb.append("mkdir -p $ETC $HOME/.ssh\n");
        sb.append("\n");
        sb.append("HOSTKEY=").append(hostkey).append("\n");
        sb.append("if [ ! -f \"$HOSTKEY\" ]; then\n");
        sb.append("  ").append(dropbearkey).append(" -t ed25519 -f \"$HOSTKEY\"\n");
        sb.append("fi\n");
        sb.append("\n");
        sb.append("PIDFILE=").append(pidfile).append("\n");
        sb.append("if [ -f \"$PIDFILE\" ]; then\n");
        sb.append("  kill $(cat \"$PIDFILE\") 2>/dev/null\n");
        sb.append("  rm -f \"$PIDFILE\"\n");
        sb.append("fi\n");
        sb.append("\n");
        sb.append("").append(dropbear).append(" -s -p ").append(port)
                .append(" -r \"$HOSTKEY\" -P \"$PIDFILE\"\n");

        PrintWriter out = new PrintWriter(script);
        out.print(sb.toString());
        out.flush();
        out.close();

        script.setReadable(true, true);
        script.setWritable(true, true);
        script.setExecutable(true, false);
    }

    /* ---- 资产解压 ---- */

    /** 入口：assets/tools 下的目录树映射到 $PREFIX（去掉 tools 前缀段） */
    private static void extractTools(AssetManager am, File prefix) throws IOException {
        String[] children = am.list("tools");
        if (children == null)
            return;
        for (String child : children)
            extractNode(am, "tools/" + child, new File(prefix, child));
    }

    private static void extractNode(AssetManager am, String assetPath, File target) throws IOException {
        // list() 对目录返回子项数组，对文件返回 null
        String[] children = am.list(assetPath);
        if (children == null) {
            // 叶子：复制文件并设执行位（静态二进制）
            ensureDir(target.getParentFile());
            copyAsset(am, assetPath, target);
            target.setReadable(true, true);
            target.setExecutable(true, false);
        } else {
            ensureDir(target);
            for (String child : children)
                extractNode(am, assetPath + "/" + child, new File(target, child));
        }
    }

    private static void copyAsset(AssetManager am, String asset, File target) throws IOException {
        InputStream is = am.open(asset, AssetManager.ACCESS_STREAMING);
        OutputStream os = new FileOutputStream(target);
        byte[] buf = new byte[32 * 1024];
        int len;
        while ((len = is.read(buf)) > 0)
            os.write(buf, 0, len);
        os.close();
        is.close();
    }

    private static void ensureDir(File dir) throws IOException {
        if (!dir.exists() && !dir.mkdirs())
            throw new IOException("cannot create dir: " + dir);
    }
}
