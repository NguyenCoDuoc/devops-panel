// DevOps Panel - bộ cài một file. Nhúng payload.zip (panel + launcher) làm resource.
// Cài cho user hiện tại, không cần quyền Admin:
//   %LOCALAPPDATA%\Programs\DevOpsPanel  + shortcut Start Menu / Desktop + mục gỡ trong Settings > Apps.
// Cấu hình người dùng ở %APPDATA%\DevOpsPanel không bị đụng tới (cài lại / nâng cấp giữ nguyên).
// Build: build-setup.ps1 (csc.exe có sẵn trong Windows - chỉ hỗ trợ C# 5, không dùng $"" / ?.)
// Tham số: /S = cài im lặng, không hỏi, không mở app.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("DevOps Panel Setup")]
[assembly: AssemblyProduct("DevOps Panel")]
[assembly: AssemblyDescription("Bộ cài DevOps Panel")]
[assembly: AssemblyVersion("1.0.4.0")]
[assembly: AssemblyFileVersion("1.0.4.0")]

static class Setup
{
    const string ProductId = "DevOpsPanel";
    const string Version = "1.0.4";
    const string ExeName = "DevOpsPanel.exe";
    const string SupportEmail = "coduoc2502@gmail.com";

    [STAThread]
    static int Main(string[] args)
    {
        bool silent = args.Any(a => a.Equals("/S", StringComparison.OrdinalIgnoreCase) || a.Equals("/silent", StringComparison.OrdinalIgnoreCase));
        string installDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", ProductId);
        string appName = ReadAppName() ?? "DevOps Panel";

        if (!silent)
        {
            string msg = "Cài đặt " + appName + " " + Version + " vào:\n" + installDir +
                "\n\nYêu cầu: Windows 10/11 (đã có sẵn PowerShell 5.1 và .NET Framework 4.8).\n" +
                "WSL, PostgreSQL, Docker, K3s là tuỳ chọn - panel tự nhận những gì máy đang có.\n\n" +
                "Hỗ trợ: " + SupportEmail + "\n\nTiếp tục?";
            if (MessageBox.Show(msg, appName + " Setup", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return 1;
        }

        try
        {
            // Đóng bản đang chạy để ghi đè được file
            foreach (var p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(ExeName)))
            {
                try { p.Kill(); p.WaitForExit(5000); } catch { }
            }

            Directory.CreateDirectory(installDir);
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            using (var zip = new ZipArchive(s, ZipArchiveMode.Read))
            {
                foreach (var entry in zip.Entries)
                {
                    if (string.IsNullOrEmpty(entry.Name)) continue;
                    string dest = Path.GetFullPath(Path.Combine(installDir, entry.FullName));
                    if (!dest.StartsWith(installDir, StringComparison.OrdinalIgnoreCase)) continue;   // chặn đường dẫn ../
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    entry.ExtractToFile(dest, true);
                }
            }

            string exe = Path.Combine(installDir, ExeName);
            string safeName = Regex.Replace(appName, "[\\\\/:*?\"<>|]", "").Trim();
            if (safeName.Length == 0) safeName = "DevOps Panel";

            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            string startup = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
            // Shortcut cũ (có thể đã đổi tên trong tab Cài đặt) -> xoá rồi tạo lại theo tên hiện tại
            bool hadStartup = RemoveOwnShortcuts(startup, exe) > 0;
            RemoveOwnShortcuts(programs, exe);
            RemoveOwnShortcuts(desktop, exe);
            CreateShortcut(Path.Combine(programs, safeName + ".lnk"), exe, installDir, appName);
            CreateShortcut(Path.Combine(desktop, safeName + ".lnk"), exe, installDir, appName);
            if (hadStartup) CreateShortcut(Path.Combine(startup, safeName + ".lnk"), exe, installDir, appName);

            using (RegistryKey k = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + ProductId))
            {
                k.SetValue("DisplayName", appName);
                k.SetValue("DisplayVersion", Version);
                k.SetValue("Publisher", "DevOps Panel");
                k.SetValue("Contact", SupportEmail);
                k.SetValue("HelpLink", "mailto:" + SupportEmail);
                k.SetValue("DisplayIcon", exe + ",0");
                k.SetValue("InstallLocation", installDir);
                k.SetValue("UninstallString", "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
                    Path.Combine(installDir, "uninstall.ps1") + "\"");
                k.SetValue("QuietUninstallString", "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" +
                    Path.Combine(installDir, "uninstall.ps1") + "\" -Quiet");
                k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                long bytes = new DirectoryInfo(installDir).GetFiles("*", SearchOption.AllDirectories).Sum(f => f.Length);
                k.SetValue("EstimatedSize", (int)(bytes / 1024), RegistryValueKind.DWord);
            }

            if (!silent)
            {
                Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = installDir, UseShellExecute = true });
            }
            return 0;
        }
        catch (Exception ex)
        {
            if (!silent) MessageBox.Show("Cài đặt thất bại:\n\n" + ex.Message + "\n\nCần hỗ trợ: " + SupportEmail, appName + " Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
    }

    /// <summary>Tên hiển thị người dùng đã đặt trong tab Cài đặt (config.json), dùng cho shortcut khi cài lại.</summary>
    static string ReadAppName()
    {
        try
        {
            string cfg = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), ProductId, "config.json");
            if (!File.Exists(cfg)) return null;
            Match m = Regex.Match(File.ReadAllText(cfg), "\"appName\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            if (!m.Success) return null;
            string name = Regex.Unescape(m.Groups[1].Value).Trim();
            return name.Length > 0 ? name : null;
        }
        catch { return null; }
    }

    static int RemoveOwnShortcuts(string folder, string exe)
    {
        int n = 0;
        if (!Directory.Exists(folder)) return 0;
        Type t = Type.GetTypeFromProgID("WScript.Shell");
        dynamic sh = Activator.CreateInstance(t);
        foreach (string lnk in Directory.GetFiles(folder, "*.lnk"))
        {
            try
            {
                dynamic s = sh.CreateShortcut(lnk);
                if (string.Equals((string)s.TargetPath, exe, StringComparison.OrdinalIgnoreCase)) { File.Delete(lnk); n++; }
            }
            catch { }
        }
        return n;
    }

    static void CreateShortcut(string path, string exe, string workDir, string description)
    {
        Type t = Type.GetTypeFromProgID("WScript.Shell");
        dynamic sh = Activator.CreateInstance(t);
        dynamic lnk = sh.CreateShortcut(path);
        lnk.TargetPath = exe;
        lnk.WorkingDirectory = workDir;
        lnk.IconLocation = exe + ",0";
        lnk.Description = description;
        lnk.Save();
    }
}
