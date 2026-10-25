// YPOS installer stub - compiled with the .NET Framework csc.exe.
// The application payload (a ZIP of the Flutter release) is embedded as the
// manifest resource "YPOS.Installer.payload.zip".
//
// Build: see tool/build_installer.ps1
// Run:   YPOS-Setup.exe            -> installs
//        YPOS-Setup.exe --uninstall -> removes program files/shortcuts (keeps data)
//
// NOTE: written for the legacy C# 5 compiler shipped with .NET Framework
// (no string interpolation, no 'using var', no dynamic).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("YPOS - Point of Sale")]
[assembly: AssemblyProduct("YPOS")]
[assembly: AssemblyCompany("YPOS")]
[assembly: AssemblyDescription("YPOS Installer")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: AssemblyCopyright("Copyright (C) 2026 YPOS")]

namespace YPOS.Installer
{
    internal static class Program
    {
        internal const string AppName = "YPOS";
        internal const string AppExe = "YPOS.exe";
        internal const string Version = "1.0.0";
        internal const string Publisher = "YPOS";

        internal static readonly string InstallDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            AppName);

        internal static string DataDir()
        {
            // path_provider_windows: %APPDATA%\<CompanyName>\<ProductName>
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                AppName,
                AppName);
        }

        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            if (args != null && args.Length > 0 &&
                args[0].Equals("--uninstall", StringComparison.OrdinalIgnoreCase))
            {
                Uninstall();
                return;
            }
            Application.Run(new InstallForm());
        }

        // ── uninstall ──────────────────────────────────────────────
        private static void Uninstall()
        {
            try
            {
                KillRunningApp();
                DeleteFile(ShortcutPath(Environment.SpecialFolder.DesktopDirectory));
                DeleteFile(ShortcutPath(Environment.SpecialFolder.Programs));
                string startMenuDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Programs), AppName);
                if (Directory.Exists(startMenuDir))
                {
                    Directory.Delete(startMenuDir, true);
                }
                try { DeleteUninstallEntry(); } catch { }
                try
                {
                    // لا نحذف مجلد data: فيه قاعدة المتجر المحمولة والصور.
                    DeleteProgramFilesKeepingData();
                }
                catch { }
                MessageBox.Show(
                    "تم إلغاء تثبيت YPOS.\n"
                    + "ملفات بيانات المتجر محفوظة في المجلد:\n"
                    + Path.Combine(InstallDir, "data"),
                    "YPOS", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show("تعذر الإلغاء: " + ex.Message, "YPOS",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // ── install steps ──────────────────────────────────────────
        internal static void KillRunningApp()
        {
            try
            {
                Process[] procs = Process.GetProcessesByName(AppName);
                foreach (Process p in procs)
                {
                    try { p.CloseMainWindow(); p.WaitForExit(3000); } catch { }
                    try { if (!p.HasExited) p.Kill(); } catch { }
                }
            }
            catch { }
        }

        internal static void ExtractPayload(Action<int, string> report)
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream s = asm.GetManifestResourceStream("YPOS.Installer.payload.zip"))
            {
                if (s == null)
                    throw new InvalidOperationException("الملف المرفق بالمثبّت غير موجود");
                using (ZipArchive zip = new ZipArchive(s, ZipArchiveMode.Read))
                {
                    int i = 0;
                    foreach (ZipArchiveEntry e in zip.Entries)
                    {
                        if (string.IsNullOrEmpty(e.Name)) continue; // مجلد
                        string outPath = Path.Combine(InstallDir, e.FullName);
                        string dir = Path.GetDirectoryName(outPath);
                        if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                        e.ExtractToFile(outPath, true);
                        i++;
                        if (report != null) report(i, e.FullName);
                    }
                    if (i == 0) throw new InvalidOperationException("الملف المرفق فارغ");
                }
            }
        }

        /// يحذف ملفات البرنامج مع الإبقاء على مجلد data (بيانات المتجر).
        internal static void DeleteProgramFilesKeepingData()
        {
            if (!Directory.Exists(InstallDir)) return;
            foreach (string file in Directory.GetFiles(InstallDir))
            {
                try { File.Delete(file); } catch { }
            }
            foreach (string dir in Directory.GetDirectories(InstallDir))
            {
                if (string.Equals(Path.GetFileName(dir), "data",
                        StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                try { Directory.Delete(dir, true); } catch { }
            }
            try
            {
                if (Directory.GetFileSystemEntries(InstallDir).Length == 0)
                    Directory.Delete(InstallDir);
            }
            catch { }
        }

        /// ينسخ مجلد الكتالوج الافتراضي (data) الموجود بجانب المثبّت إلى مجلد
        /// التثبيت، فيجد التطبيق الكتالوج المرفق عند أول تشغيل. لا يفعل شيئًا
        /// إن لم يكن المجلد موجودًا (نسخة بلا كتالوج مرفق).
        /// **لا يستبدل أي ملف موجود** — خصوصاً bookstore_pos.sqlite الذي قد
        /// يكون قاعدة المتجر الحية (نسخة محمولة) بعد الاستخدام.
        internal static void CopyBundledData(Action<int, string> report)
        {
            string setupDir = Path.GetDirectoryName(Application.ExecutablePath);
            string src = Path.Combine(setupDir, "data");
            if (!Directory.Exists(src)) return;
            string dst = Path.Combine(InstallDir, "data");
            string[] files = Directory.GetFiles(src, "*", SearchOption.AllDirectories);
            int n = 0;
            foreach (string f in files)
            {
                string rel = f.Substring(src.Length).TrimStart(
                    Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                string outPath = Path.Combine(dst, rel);
                string dir = Path.GetDirectoryName(outPath);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                if (!File.Exists(outPath)) File.Copy(f, outPath, false);
                n++;
                if (report != null && (n % 500 == 0)) report(n, rel);
            }
            if (report != null) report(n, "data/");
        }

        /// ينقل بيانات المتجر القديمة إلى مسار YPOS الجديد (نسخ فقط، بلا حذف).
        /// يُرجع رسالة عند الترحيل، أو null عند عدم وجود بيانات قديمة.
        internal static string MigrateLegacyData()
        {
            string roaming = Environment.GetFolderPath(
                Environment.SpecialFolder.ApplicationData);
            string target = DataDir();
            string legacy = Path.Combine(roaming, "com.bookstore", "bookstore_pos");
            if (!Directory.Exists(legacy)) return null;
            string dbTarget = Path.Combine(target, "bookstore_pos.sqlite");
            if (File.Exists(dbTarget)) return null; // البيانات موجودة بالفعل
            CopyDirectory(legacy, target);
            return legacy;
        }

        internal static void CreateShortcuts()
        {
            string exe = Path.Combine(InstallDir, AppExe);
            try
            {
                CreateShortcut(ShortcutPath(Environment.SpecialFolder.DesktopDirectory), exe);
            }
            catch { }
            try
            {
                CreateShortcut(ShortcutPath(Environment.SpecialFolder.Programs), exe);
            }
            catch { }
        }

        private static string ShortcutPath(Environment.SpecialFolder folder)
        {
            string dir = Environment.GetFolderPath(folder);
            if (folder == Environment.SpecialFolder.Programs)
                dir = Path.Combine(dir, AppName);
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            return Path.Combine(dir, AppName + ".lnk");
        }

        private static void CreateShortcut(string lnkPath, string target)
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            if (t == null) return;
            object shell = Activator.CreateInstance(t);
            Type shellType = shell.GetType();
            object link = shellType.InvokeMember("CreateShortcut",
                BindingFlags.InvokeMethod, null, shell, new object[] { lnkPath });
            Type linkType = link.GetType();
            linkType.InvokeMember("TargetPath", BindingFlags.SetProperty, null,
                link, new object[] { target });
            linkType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null,
                link, new object[] { InstallDir });
            linkType.InvokeMember("IconLocation", BindingFlags.SetProperty, null,
                link, new object[] { target + ",0" });
            linkType.InvokeMember("Description", BindingFlags.SetProperty, null,
                link, new object[] { AppName + " - Point of Sale" });
            // Save is a method of the shortcut object (not of the shell).
            linkType.InvokeMember("Save", BindingFlags.InvokeMethod, null,
                link, new object[0]);
        }

        internal static string UninstallKeyPath()
        {
            return @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + AppName;
        }

        /// يحذف مدخل الإزالة عبر reg.exe (RegistryKey.Delete غير متاح في
        /// مُجمّع C# القديم على كل الأنظمة).
        internal static void DeleteUninstallEntry()
        {
            try
            {
                Process p = Process.Start(new ProcessStartInfo("reg.exe",
                    "delete \"HKCU\\" + UninstallKeyPath() + "\" /f")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                });
                p.WaitForExit(5000);
            }
            catch { }
        }

        internal static void WriteUninstallEntry()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(
                    UninstallKeyPath()))
                {
                    k.SetValue("DisplayName", AppName + " - Point of Sale");
                    k.SetValue("DisplayVersion", Version);
                    k.SetValue("Publisher", Publisher);
                    k.SetValue("InstallLocation", InstallDir);
                    k.SetValue("DisplayIcon", Path.Combine(InstallDir, AppExe));
                    k.SetValue("UninstallString",
                        "\"" + Application.ExecutablePath + "\" --uninstall");
                    k.SetValue("NoModify", 1);
                    k.SetValue("NoRepair", 1);
                }
            }
            catch { }
        }

        internal static void CopyDirectory(string srcDir, string dstDir)
        {
            Directory.CreateDirectory(dstDir);
            foreach (string file in Directory.GetFiles(srcDir))
            {
                File.Copy(file, Path.Combine(dstDir, Path.GetFileName(file)), true);
            }
            foreach (string dir in Directory.GetDirectories(srcDir))
            {
                CopyDirectory(dir, Path.Combine(dstDir, Path.GetFileName(dir)));
            }
        }

        private static void DeleteFile(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }
    }

    // ── نافذة التثبيت ───────────────────────────────────────────
    internal class InstallForm : Form
    {
        private readonly Label _status;
        private readonly ProgressBar _bar;
        private readonly CheckBox _launch;
        private readonly Button _installBtn;
        private readonly Button _cancelBtn;
        private readonly TextBox _log;
        private volatile bool _busy;

        internal InstallForm()
        {
            Text = Program.AppName + " - تثبيت";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(520, 340);
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            Font = new Font("Segoe UI", 9F);

            var title = new Label
            {
                Text = "تثبيت برنامج " + Program.AppName,
                Font = new Font("Segoe UI", 16F, FontStyle.Bold),
                AutoSize = true,
                Dock = DockStyle.Top,
                Padding = new Padding(16, 16, 16, 4),
            };

            _status = new Label
            {
                Text = "جاهز للتثبيت في: " + Program.InstallDir,
                AutoSize = false,
                Height = 34,
                Dock = DockStyle.Top,
                Padding = new Padding(16, 0, 16, 0),
                ForeColor = Color.DimGray,
            };

            _bar = new ProgressBar
            {
                Style = ProgressBarStyle.Continuous,
                Dock = DockStyle.Top,
                Height = 20,
                Margin = new Padding(16, 0, 16, 0),
            };

            _launch = new CheckBox
            {
                Text = "تشغيل " + Program.AppName + " بعد انتهاء التثبيت",
                Checked = true,
                AutoSize = true,
                Dock = DockStyle.Top,
                Padding = new Padding(16, 10, 16, 0),
            };

            _log = new TextBox
            {
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                Dock = DockStyle.Fill,
                BackColor = Color.White,
                Font = new Font("Consolas", 8.5F),
                Margin = new Padding(16, 8, 16, 0),
            };

            _installBtn = new Button
            {
                Text = "تثبيت الآن",
                Size = new Size(150, 46),
                Dock = DockStyle.Right,
                Font = new Font("Segoe UI", 11F, FontStyle.Bold),
            };
            _installBtn.Click += OnInstall;

            _cancelBtn = new Button
            {
                Text = "إغلاق",
                Size = new Size(120, 46),
                Dock = DockStyle.Right,
                Font = new Font("Segoe UI", 11F),
            };
            _cancelBtn.Click += delegate { if (!_busy) Close(); };

            var buttons = new Panel
            {
                Dock = DockStyle.Top,
                Height = 62,
                Padding = new Padding(16, 8, 16, 8),
            };
            buttons.Controls.Add(_installBtn);
            buttons.Controls.Add(_cancelBtn);

            var logHost = new Panel
            {
                Dock = DockStyle.Fill,
                Padding = new Padding(16, 8, 16, 12),
            };
            logHost.Controls.Add(_log);

            // DockStyle.Top: last added ends up highest.
            Controls.Add(logHost);
            Controls.Add(buttons);
            Controls.Add(_launch);
            Controls.Add(_bar);
            Controls.Add(_status);
            Controls.Add(title);
        }

        private void Log(string s)
        {
            if (InvokeRequired) { BeginInvoke(new MethodInvoker(delegate { Log(s); })); return; }
            _log.AppendText(s + Environment.NewLine);
            _log.SelectionStart = _log.TextLength;
            _log.ScrollToCaret();
        }

        private void SetStatus(string s)
        {
            if (InvokeRequired) { BeginInvoke(new MethodInvoker(delegate { SetStatus(s); })); return; }
            _status.Text = s;
        }

        private void OnInstall(object sender, EventArgs e)
        {
            if (_busy) return;
            _busy = true;
            _installBtn.Enabled = false;
            _cancelBtn.Enabled = false;
            _bar.Style = ProgressBarStyle.Marquee;
            SetStatus("جارٍ التثبيت...");

            Thread worker = new Thread(delegate()
            {
                try
                {
                    Log("إيقاف أي نسخة قيد التشغيل...");
                    Program.KillRunningApp();

                    Log("إنشاء مجلد التثبيت: " + Program.InstallDir);
                    Directory.CreateDirectory(Program.InstallDir);

                    Log("نسخ ملفات البرنامج...");
                    Program.ExtractPayload(delegate(int n, string name)
                    {
                        Log("  + " + name);
                    });

                    Log("نسخ الكتالوج الافتراضي (منتجات + صور)...");
                    Program.CopyBundledData(delegate(int n, string name)
                    {
                        SetStatus("نسخ الكتالوج الافتراضي... " + n + " ملف");
                    });

                    Log("نقل بيانات المتجر إن وُجدت...");
                    string legacy = Program.MigrateLegacyData();
                    if (legacy != null)
                        Log("تم ترحيل البيانات من: " + legacy);
                    else
                        Log("لا توجد بيانات سابقة للترحيل (أو موجودة مسبقاً).");

                    Log("إنشاء اختصارات سطح المكتب وقائمة ابدأ...");
                    Program.CreateShortcuts();

                    Log("تسجيل البرنامج في قائمة التطبيقات...");
                    Program.WriteUninstallEntry();

                    Log("اكتمل التثبيت بنجاح.");
                    OnInstalled(true, null);
                }
                catch (Exception ex)
                {
                    OnInstalled(false, ex);
                }
            });
            worker.IsBackground = true;
            worker.Start();
        }

        private void OnInstalled(bool ok, Exception error)
        {
            BeginInvoke(new MethodInvoker(delegate()
            {
                _busy = false;
                _bar.Style = ProgressBarStyle.Continuous;
                _bar.Value = ok ? 100 : 0;
                if (!ok)
                {
                    _installBtn.Enabled = true;
                    _cancelBtn.Enabled = true;
                    SetStatus("فشل التثبيت.");
                    MessageBox.Show("تعذر إكمال التثبيت:\n" + (error == null ? "" : error.Message),
                        Program.AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                SetStatus("تم التثبيت بنجاح في: " + Program.InstallDir);
                MessageBox.Show(
                    "تم تثبيت " + Program.AppName + " بنجاح.\n\nالمسار: " + Program.InstallDir,
                    Program.AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
                if (_launch.Checked)
                {
                    try
                    {
                        Process.Start(new ProcessStartInfo(
                            Path.Combine(Program.InstallDir, Program.AppExe))
                        { WorkingDirectory = Program.InstallDir });
                    }
                    catch { }
                }
                Close();
            }));
        }
    }
}