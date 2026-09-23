/*
 * 日志工具类 — 将运行日志写入外部 files/logs/（优先）与内部 files/logs/
 * 用于 Android 4.4 上诊断崩溃问题
 */

package com.termoneplus.utils;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class RunLog {
    private static final String TAG = "TermOnePlus";
    private static File[] logDirs;
    private static final SimpleDateFormat DATE_FMT =
            new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US);

    /**
     * 初始化日志目录，必须在 Application.onCreate 最早期调用。
     * 同时写内部存储与外部应用专属目录，便于无 root 查看。
     */
    public static void init(Context context) {
        try {
            File internal = new File(context.getFilesDir(), "logs");
            File external = null;
            try {
                File ext = context.getExternalFilesDir(null);
                if (ext != null) external = new File(ext, "logs");
            } catch (Throwable ignore) {
            }

            if (external != null) {
                logDirs = new File[]{external, internal};
            } else {
                logDirs = new File[]{internal};
            }

            for (File d : logDirs) {
                if (!d.exists()) d.mkdirs();
            }
            info("=== RunLog initialized ===");
            for (File d : logDirs) {
                info("logDir: " + d.getAbsolutePath() + " exists=" + d.exists() + " canWrite=" + d.canWrite());
            }
        } catch (Throwable t) {
            Log.e(TAG, "RunLog.init failed", t);
        }
    }

    /** 兼容旧签名：仅内部存储 */
    public static void init(File filesDir) {
        try {
            logDirs = new File[]{new File(filesDir, "logs")};
            if (!logDirs[0].exists()) logDirs[0].mkdirs();
            info("=== RunLog initialized (legacy) dir=" + logDirs[0].getAbsolutePath() + " ===");
        } catch (Throwable t) {
            Log.e(TAG, "RunLog.init failed", t);
        }
    }

    public static void info(String msg) {
        Log.i(TAG, msg);
        write("I", msg, null);
    }

    public static void warn(String msg) {
        Log.w(TAG, msg);
        write("W", msg, null);
    }

    public static void error(String msg) {
        Log.e(TAG, msg);
        write("E", msg, null);
    }

    public static void error(String msg, Throwable t) {
        Log.e(TAG, msg, t);
        write("E", msg, t);
    }

    public static void crash(Throwable t) {
        Log.e(TAG, "CRASH", t);
        write("F", "CRASH: " + t, t);
    }

    private static synchronized void write(String level, String msg, Throwable t) {
        if (logDirs == null) return;
        String date = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
        for (File dir : logDirs) {
            try {
                if (dir == null) continue;
                if (!dir.exists()) dir.mkdirs();
                File f = new File(dir, "run-" + date + ".log");
                FileWriter fw = new FileWriter(f, true);
                PrintWriter pw = new PrintWriter(fw);
                pw.println(DATE_FMT.format(new Date()) + " [" + level + "] " + msg);
                if (t != null) {
                    StringWriter sw = new StringWriter();
                    t.printStackTrace(new PrintWriter(sw));
                    pw.print(sw.toString());
                }
                pw.close();
                fw.close();
            } catch (Throwable ignore) {
            }
        }
    }
}
