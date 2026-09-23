/*
 * 日志工具类 — 将运行日志写入 $FILES/logs/
 * 用于 Android 4.4 上诊断崩溃问题
 */

package com.termoneplus.utils;

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
    private static File logDir;
    private static final SimpleDateFormat DATE_FMT =
            new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US);

    /** 初始化日志目录，必须在 Application.onCreate 最早期调用 */
    public static void init(File filesDir) {
        try {
            logDir = new File(filesDir, "logs");
            if (!logDir.exists()) logDir.mkdirs();
            info("=== RunLog initialized, dir=" + logDir.getAbsolutePath() + " ===");
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
        if (logDir == null) return;
        try {
            // 按天分文件，保留最近 7 天
            String date = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
            File f = new File(logDir, "run-" + date + ".log");
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
