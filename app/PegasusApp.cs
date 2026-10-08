// Develop Workspace - launcher .exe: chạy PegasusPanel.ps1 bên trong tiến trình của chính nó
// để Windows coi đây là một app riêng (icon, Start Menu, ghim taskbar, gỡ trong Settings).
// Build: xem install.ps1
using System;
using System.IO;
using System.Reflection;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Develop Workspace")]
[assembly: AssemblyProduct("Develop Workspace")]
[assembly: AssemblyCompany("Develop Workspace")]
[assembly: AssemblyDescription("Bảng điều khiển Ubuntu (WSL), PostgreSQL, Docker, sức khỏe máy")]
[assembly: AssemblyVersion("1.0.5.0")]
[assembly: AssemblyFileVersion("1.0.5.0")]

static class Program
{
    [STAThread]
    static int Main()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
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

        try
        {
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddCommand(script);
                    ps.Invoke();
                }
            }
        }
        catch (Exception ex)
        {
            File.AppendAllText(Path.Combine(dir, "app-error.log"), DateTime.Now + "  " + ex + Environment.NewLine);
            MessageBox.Show("Develop Workspace gặp lỗi:\n\n" + ex.Message, "Develop Workspace",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
