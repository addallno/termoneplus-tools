#!/usr/bin/env python3
# 应用 dropbear Android 适配补丁（无 /etc/passwd 环境的 getpwnam 注入）
# 用法: python3 dropbear-android-user.py <dropbear-src-dir>
# 对 dropbear 2026.94 源码做 3 处精确字符串替换，anchor 不匹配则报错退出。

import os
import sys

HOME_DEFAULT = "/data/data/com.termtools.box/files/home"

def patch_file(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if old not in content:
        print("ERROR: anchor not found in %s: %s" % (path, label))
        sys.exit(1)
    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: patched %s (%s)" % (path, label))

def main():
    if len(sys.argv) != 2:
        print("usage: %s <dropbear-src-dir>" % sys.argv[0])
        sys.exit(1)
    src = sys.argv[1]

    # 1) common-session.c fill_passwd(): getpwnam 失败时注入合成 passwd
    common_old = """\tpw = getpwnam(username);
\tif (!pw) {
\t\treturn;
\t}
"""
    common_new = """\tpw = getpwnam(username);
\tif (!pw) {
\t\t/* Android: the app uid has no /etc/passwd entry. Inject a
\t\t * synthetic passwd using the real (current) uid/gid. */
\t\tstatic struct passwd apw;
\t\tstatic char apw_name[64], apw_dir[256], apw_shell[64], apw_pass[8];
\t\tconst char *home = getenv("HOME");
\t\tmemset(&apw, 0, sizeof(apw));
\t\tsnprintf(apw_name, sizeof(apw_name), "%s", username ? username : "root");
\t\tapw.pw_name = apw_name;
\t\tapw.pw_uid = getuid();
\t\tapw.pw_gid = getgid();
\t\tif (home && *home)
\t\t\tsnprintf(apw_dir, sizeof(apw_dir), "%s", home);
\t\telse
\t\t\tsnprintf(apw_dir, sizeof(apw_dir), "%s", HOME_DEFAULT);
\t\tapw.pw_dir = apw_dir;
\t\tstrcpy(apw_shell, "/system/bin/sh");
\t\tapw.pw_shell = apw_shell;
\t\tstrcpy(apw_pass, "!!");
\t\tapw.pw_passwd = apw_pass;
\t\tpw = &apw;
\t}
"""
    common_new = common_new.replace("HOME_DEFAULT", '"%s"' % HOME_DEFAULT)
    patch_file(os.path.join(src, "common-session.c"), common_old, common_new, "fill_passwd")

    # 2) svr-chansession.c sessionpty(): 复用 authstate 的 uid/gid
    pty_old = """\tpw = getpwnam(ses.authstate.pw_name);
\tif (!pw)
\t\tdropbear_exit("getpwnam failed after succeeding previously");
"""
    pty_new = """\tpw = getpwnam(ses.authstate.pw_name);
\tif (!pw) {
\t\t/* Android: no /etc/passwd; reuse authstate identity. */
\t\tstatic struct passwd apw;
\t\tmemset(&apw, 0, sizeof(apw));
\t\tapw.pw_name = ses.authstate.pw_name;
\t\tapw.pw_uid = ses.authstate.pw_uid;
\t\tapw.pw_gid = ses.authstate.pw_gid;
\t\tapw.pw_dir = ses.authstate.pw_dir;
\t\tapw.pw_shell = ses.authstate.pw_shell;
\t\tpw = &apw;
\t}
"""
    patch_file(os.path.join(src, "svr-chansession.c"), pty_old, pty_new, "sessionpty")

    # 3) loginrec.c login_init_entry(): 用真实 uid 代替 getpwnam
    login_old = """\t\tpw = getpwnam(li->username);
\t\tif (pw == NULL)
\t\t\tdropbear_exit("login_init_entry: Cannot find user \\"%s\\"",
\t\t\t\t\tli->username);
\t\tli->uid = pw->pw_uid;
"""
    login_new = """\t\tpw = getpwnam(li->username);
\t\tif (pw == NULL) {
\t\t\t/* Android: no /etc/passwd; fall back to the real uid. */
\t\t\tstatic struct passwd apw;
\t\t\tmemset(&apw, 0, sizeof(apw));
\t\t\tapw.pw_uid = getuid();
\t\t\tpw = &apw;
\t\t}
\t\tli->uid = pw->pw_uid;
"""
    patch_file(os.path.join(src, "loginrec.c"), login_old, login_new, "login_init_entry")

    # 4) sysoptions.h: 无 /etc/shells 时认可 /system/bin/sh（默认只有 /bin/sh /bin/csh）
    shells_old = '#define COMPAT_USER_SHELLS "/bin/sh","/bin/csh"\n'
    shells_new = '#define COMPAT_USER_SHELLS "/system/bin/sh"\n'
    patch_file(os.path.join(src, "sysoptions.h"), shells_old, shells_new, "COMPAT_USER_SHELLS")

    print("all patches applied")

if __name__ == "__main__":
    main()
