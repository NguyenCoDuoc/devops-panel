// Develop Workspace - launcher .exe: chạy PegasusPanel.ps1 bên trong tiến trình của chính nó
// để Windows coi đây là một app riêng (icon, Start Menu, ghim taskbar, gỡ trong Settings).
// Build: xem install.ps1 hoặc build-setup.ps1
using System;
using System.IO;
using System.Reflection;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Develop Workspace")]
[assembly: AssemblyProduct("Develop Workspace")]
[assembly: AssemblyCompany("Develop Workspace")]
[assembly: AssemblyDescription("Bảng điều khiển Ubuntu (WSL), PostgreSQL, Docker, K3s, sức khỏe máy")]
[assembly: AssemblyVersion("1.0.8.0")]
[assembly: AssemblyFileVersion("1.0.8.0")]

static class Program
{
    [DllImport("shell32.dll", SetLastError = true)]
    static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

    [STAThread]
    static int Main()
    {
        try
        {
            // Đăng ký AppUserModelID để Windows Taskbar và Alt+Tab nhận diện app độc lập, không gộp vào PowerShell / CMD
            SetCurrentProcessExplicitAppUserModelID("Sunhouse.DevOps.Workspace");
        }
        catch { }

        string dir = AppDomain.CurrentDomain.BaseDirectory;
        try { Directory.SetCurrentDirectory(dir); } catch { }

        string script = Path.Combine(dir, "PegasusPanel.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Không tìm thấy PegasusPanel.ps1 cạnh file exe:\n" + script, "Develop Workspace",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        var iss = InitialSessionState.CreateDefault();
        iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        iss.ApartmentState = ApartmentState.STA;           // WinForms cần STA
        iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
        iss.Variables.Add(new SessionStateVariableEntry("PSScriptRoot", dir, "Script directory"));

        try
        {
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.Open();
                rs.SessionStateProxy.SetVariable("PSScriptRoot", dir);
                try { rs.SessionStateProxy.Path.SetLocation(dir); } catch { }

                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(string.Format("& '{0}'", script.Replace("'", "''")));
                    ps.Invoke();

                    if (ps.HadErrors)
                    {
                        string errs = "";
                        foreach (var err in ps.Streams.Error)
                        {
                            if (err != null) errs += err.ToString() + Environment.NewLine;
                        }
                        if (!string.IsNullOrEmpty(errs))
                        {
                            File.AppendAllText(Path.Combine(dir, "app-error.log"),
                                DateTime.Now + " [PowerShell Pipeline Error]:" + Environment.NewLine + errs + Environment.NewLine);
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            // Nếu là ExitException do lệnh exit chủ động từ script (ví dụ mutex) thì thoát bình thường
            string typeName = ex.GetType().Name;
            if (typeName == "ExitException" || (ex.InnerException != null && ex.InnerException.GetType().Name == "ExitException"))
            {
                return 0;
            }

            File.AppendAllText(Path.Combine(dir, "app-error.log"), DateTime.Now + "  " + ex + Environment.NewLine);
            MessageBox.Show("Develop Workspace gặp lỗi:\n\n" + ex.Message, "Develop Workspace",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
