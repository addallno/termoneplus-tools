/*
 * Copyright (C) 2018-2026 Roumen Petrov.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.termoneplus;

import android.content.SharedPreferences;
import android.content.res.AssetManager;
import android.text.TextUtils;

import androidx.preference.PreferenceManager;

import com.google.android.material.color.DynamicColors;
import com.termoneplus.utils.RunLog;
import com.termoneplus.utils.ThemeManager;

import android.util.Log;

import java.io.File;
import java.util.concurrent.Executors;


public class Application extends android.app.Application {
    public static final String ID = BuildConfig.APPLICATION_ID;
    public static final String VER = BuildConfig.VERSION_NAME;

    public static final String APP_TAG = "TermOnePlus";

    public static final String NOTIFICATION_CHANNEL_SESSIONS = BuildConfig.APPLICATION_ID + ".sessions";

    public static final String ACTION_OPEN_NEW_WINDOW = BuildConfig.APPLICATION_ID + ".OPEN_NEW_WINDOW";
    public static final String ACTION_RUN_SHORTCUT = BuildConfig.APPLICATION_ID + ".RUN_SHORTCUT";
    public static final String ACTION_RUN_SCRIPT = BuildConfig.APPLICATION_ID + ".RUN_SCRIPT";

    public static final String ARGUMENT_TARGET_WINDOW = "target_window";
    public static final String ARGUMENT_WINDOW_ID = "window_id";
    public static final String ARGUMENT_SHELL_COMMAND = "com.termoneplus.Command";
    public static final String ARGUMENT_WINDOW_HANDLE = "com.termoneplus.WindowHandle";

    public static Settings settings;

    private static File xbindir;

    private static File rootdir;
    private static File prefixdir;
    private static File usrdir;
    private static File etcdir;
    private static File libdir;
    private static File homedir;
    private static File tmpdir;
    private static File cachedir;


    public static File getRootDir() {
        return rootdir;
    }

    public static File getPrefixDir() {
        return usrdir;
    }

    public static File getHomeDir() {
        return homedir;
    }

    public static File getTmpDir() {
        return tmpdir;
    }

    public static String getTmpPath() {
        return getTmpDir().getAbsolutePath();
    }

    public static File getScriptFile() {
        return new File(etcdir, "mkshrc");
    }

    public static String getScriptFilePath() {
        return getScriptFile().getPath();
    }

    public static String buildPATH() {
        StringBuilder path = new StringBuilder();

        // $PREFIX/bin
        path.append(usrdir.getPath()).append("/bin");

        // $HOME subdirectories (Termux-style)
        String homePath = homedir.getAbsolutePath();
        path.append(File.pathSeparator).append(homePath).append("/bin");
        path.append(File.pathSeparator).append(homePath).append("/tools/bin");
        path.append(File.pathSeparator).append(homePath).append("/cmd");
        path.append(File.pathSeparator).append(homePath).append("/utils");

        // xbindir (native libs / fallback)
        if (!xbindir.equals(new File(usrdir, "bin"))) {
            path.append(File.pathSeparator).append(xbindir.getPath());
        }

        // system PATH
        String sysPath = System.getenv("PATH");
        if (!TextUtils.isEmpty(sysPath))
            path.append(File.pathSeparator).append(sysPath);

        return path.toString();
    }

    public static String buildLoaderLibraryPath(String extra) {
        String path = Application.libdir.getPath();

        if (!TextUtils.isEmpty(extra))
            path += File.pathSeparator + extra;

        String orig = System.getenv("LD_LIBRARY_PATH");
        if (!TextUtils.isEmpty(orig))
            path += File.pathSeparator + orig;

        return path;
    }

    @Override
    public void onCreate() {
        super.onCreate();

        // 初始化日志（最早，用于诊断崩溃）
        RunLog.init(getFilesDir());
        RunLog.info("Application.onCreate start, ID=" + ID + " VER=" + VER);

        try {
            DynamicColors.applyToActivitiesIfAvailable(this);
            RunLog.info("DynamicColors applied");
        } catch (Throwable t) {
            RunLog.error("DynamicColors failed", t);
            // 继续执行，DynamicColors 失败不应导致崩溃
        }

        rootdir = getFilesDir().getParentFile();
        prefixdir = getFilesDir();
        usrdir = new File(prefixdir, "usr");
        etcdir = new File(usrdir, "etc");
        libdir = new File(usrdir, "lib");
        tmpdir = new File(usrdir, "tmp");
        homedir = new File(prefixdir, "home");
        cachedir = getCacheDir();
        RunLog.info("dirs: root=" + rootdir + " usr=" + usrdir + " home=" + homedir);

        // create directory structure
        try {
            Installer.install_directory(usrdir, false);
            Installer.install_directory(etcdir, false);
            Installer.install_directory(libdir, false);
            Installer.install_directory(tmpdir, false);
            Installer.install_directory(homedir, false);
            Installer.install_directory(new File(homedir, ".ssh"), false);
            RunLog.info("directories created");
        } catch (Throwable t) {
            RunLog.error("directory creation failed", t);
            throw new RuntimeException("Directory setup failed", t);
        }

        // copy native libraries to $PREFIX/lib
        try {
            linkNativeLibs();
            RunLog.info("native libs linked");
        } catch (Throwable t) {
            RunLog.error("linkNativeLibs failed", t);
            // 继续执行，native libs 失败不一定致命
        }

        try {
            setupPreferences();
            RunLog.info("preferences setup");
        } catch (Throwable t) {
            RunLog.error("setupPreferences failed", t);
            throw new RuntimeException("Preferences setup failed", t);
        }

        try {
            ThemeManager.migrateFileSelectionThemeMode(this);
            TypefaceSetting.create(getAssets());
            RunLog.info("theme setup done");
        } catch (Throwable t) {
            RunLog.error("theme setup failed", t);
            // 继续执行，theme 失败不应阻止启动
        }

        try {
            install_skeleton();
            Installer.installToolsToPrefix(getAssets());
            RunLog.info("skeleton and tools installed");
        } catch (Throwable t) {
            RunLog.error("install_skeleton/tools failed", t);
            throw new RuntimeException("Tools install failed", t);
        }

        // xbindir: try libdir first, fallback to usrdir/bin
        try {
            xbindir = libdir;
            File exe = new File(xbindir, Installer.APPINFO_COMMAND);
            if (!exe.canExecute()) {
                File binDir = new File(usrdir, "bin");
                Installer.install_directory(binDir, false);
                xbindir = binDir;
                Installer.copy_executable(exe, xbindir);
            }

            Installer.installAppScriptFile();
            RunLog.info("xbindir setup done, xbindir=" + xbindir);
        } catch (Throwable t) {
            RunLog.error("xbindir/appscript setup failed", t);
            // 继续执行
        }

        // start dropbear SSH server in background
        try {
            startDropbear();
            RunLog.info("startDropbear called");
        } catch (Throwable t) {
            RunLog.error("startDropbear failed", t);
            // 继续执行，SSH 失败不应阻止 app 启动
        }

        RunLog.info("Application.onCreate finished OK");

        // 安装全局异常处理器，捕获所有未处理崩溃
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            RunLog.crash(throwable);
            // 重新抛出，让系统显示崩溃对话框
            System.exit(1);
        });
    }

    private void linkNativeLibs() {
        File nativeDir = new File(getApplicationInfo().nativeLibraryDir);
        if (!nativeDir.exists()) return;

        File[] libs = nativeDir.listFiles();
        if (libs == null) return;

        for (File lib : libs) {
            File target = new File(libdir, lib.getName());
            if (!target.exists()) {
                Installer.copy_executable(lib, libdir);
            }
        }
    }

    private void setupPreferences() {
        boolean updated = false;

        SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(getApplicationContext());
        SharedPreferences.Editor editor = prefs.edit();

        String pref_home_path = getString(R.string.key_home_path_preference);
        if (!prefs.contains(pref_home_path)) {
            String path = homedir.getAbsolutePath();
            editor.putString(pref_home_path, path);
            updated = true;
        }

        // clean-up obsolete preferences:
        if (prefs.contains("allow_prepend_path")) {
            editor.remove("allow_prepend_path");
            updated = true;
        }
        if (prefs.contains("do_path_extensions")) {
            editor.remove("do_path_extensions");
            updated = true;
        }

        if (updated) editor.apply();

        settings = new Settings(this, prefs);
    }

    private boolean install_skeleton() {
        String asset_path = "skel";

        AssetManager am = getAssets();
        try {
            String[] list = am.list(asset_path);
            if (list == null) return true;
            for (String item : list)
                if (!install_skeleton_item(homedir, am, asset_path, item))
                    return false;
        } catch (Exception ignore) {
        }
        return true;
    }

    protected final boolean install_skeleton_item(File home, AssetManager am, String asset_path, String item) {
        File target = new File(home, "." + item);

        if (target.exists()) return true;

        return Installer.install_asset(am, asset_path + "/" + item, target);
    }

    private void startDropbear() {
        Executors.newSingleThreadExecutor().execute(() -> {
            try {
                File dropbearBin = new File(usrdir, "bin/dropbear");
                if (!dropbearBin.exists() || !dropbearBin.canExecute()) {
                    Log.w(APP_TAG, "dropbear not found or not executable");
                    return;
                }

                // generate host keys if missing
                File rsaKey = new File(etcdir, "dropbear_rsa_host_key");
                File dssKey = new File(etcdir, "dropbear_dss_host_key");
                File ecdsaKey = new File(etcdir, "dropbear_ecdsa_host_key");

                if (!rsaKey.exists() && !dssKey.exists() && !ecdsaKey.exists()) {
                    File dropbearkey = new File(usrdir, "bin/dropbearkey");
                    if (dropbearkey.exists() && dropbearkey.canExecute()) {
                        Runtime.getRuntime().exec(new String[]{
                                dropbearkey.getAbsolutePath(),
                                "-t", "rsa",
                                "-f", rsaKey.getAbsolutePath()
                        }).waitFor();
                        Runtime.getRuntime().exec(new String[]{
                                dropbearkey.getAbsolutePath(),
                                "-t", "dss",
                                "-f", dssKey.getAbsolutePath()
                        }).waitFor();
                        Runtime.getRuntime().exec(new String[]{
                                dropbearkey.getAbsolutePath(),
                                "-t", "ecdsa",
                                "-f", ecdsaKey.getAbsolutePath()
                        }).waitFor();
                    }
                }

                // start dropbear on port 8022
                Runtime.getRuntime().exec(new String[]{
                        dropbearBin.getAbsolutePath(),
                        "-p", "0.0.0.0:8022",
                        "-r", etcdir.getAbsolutePath(),
                        "-E",
                        "-F"
                });
                Log.i(APP_TAG, "dropbear SSH server started on port 8022");
            } catch (Exception e) {
                Log.e(APP_TAG, "Failed to start dropbear", e);
            }
        });
    }
}
