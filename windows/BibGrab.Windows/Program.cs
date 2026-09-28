using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace BibGrab;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Contains("--self-test")) return CheckSettings();
        using var mutex = new Mutex(true, @"Local\BibGrab.Windows", out var first);
        if (!first)
        {
            MessageBox.Show("BibGrab is already running. Open it from the system tray (including hidden icons).", "BibGrab");
            return 0;
        }
        using var context = new TrayContext(!args.Contains("--background"));
        Application.Run(context);
        return 0;
    }

    private static int CheckSettings()
    {
        var directory = Path.Combine(Path.GetTempPath(), "BibGrab-check-" + Guid.NewGuid());
        try
        {
            new TokenStore(directory).Save(" sample-test-token ");
            if (new TokenStore(directory).Load() != "sample-test-token") return 1;
            if (System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(Path.Combine(directory, "ads-token.dat"))).Contains("sample-test-token")) return 1;
            new TokenStore(directory).Save("");
            if (File.Exists(Path.Combine(directory, "ads-token.dat"))) return 1;
            using var form = new CitationForm(new TokenStore(directory));
            _ = form.Handle;
            return 0;
        }
        catch { return 1; }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }
}

internal sealed class TrayContext : ApplicationContext
{
    private readonly CitationForm form = new(new TokenStore());
    private readonly NotifyIcon tray;

    public TrayContext(bool show)
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Open BibGrab", null, (_, _) => Open());
        menu.Items.Add("Set ADS Token…", null, (_, _) => { Open(); form.EditToken(); });
        var startup = new ToolStripMenuItem("Launch at Login") { Checked = Startup.Enabled };
        startup.Click += (_, _) =>
        {
            try { Startup.Enabled = !Startup.Enabled; startup.Checked = Startup.Enabled; }
            catch { MessageBox.Show("Could not change Launch at Login.", "BibGrab"); }
        };
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => ExitThread());
        tray = new NotifyIcon { Icon = SystemIcons.Application, Text = "BibGrab", ContextMenuStrip = menu, Visible = true };
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) Open(); };
        if (show) Open();
    }

    private void Open() { form.Show(); form.WindowState = FormWindowState.Normal; form.Activate(); form.FocusInput(); }
    protected override void ExitThreadCore()
    {
        tray.Visible = false;
        tray.ContextMenuStrip?.Dispose();
        tray.Dispose();
        form.Dispose();
        base.ExitThreadCore();
    }
}

internal sealed class CitationForm : Form
{
    private readonly TokenStore tokens;
    private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(25) };
    private readonly TextBox input = new() { Dock = DockStyle.Fill, PlaceholderText = "10.1103/PhysRev.47.777", AccessibleName = "DOI or arXiv link" };
    private readonly TextBox output = new() { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, AccessibleName = "BibTeX citation" };
    private readonly Label status = new() { Dock = DockStyle.Fill, AutoSize = true, Text = "Ready. Paste a DOI or arXiv link." };
    private readonly Button lookup = new() { Text = "Get BibTeX", AutoSize = true };
    private readonly Button copy = new() { Text = "Copy", AutoSize = true, Enabled = false };
    private CancellationTokenSource? pending;

    public CitationForm(TokenStore store)
    {
        tokens = store;
        Text = "BibGrab";
        Icon = SystemIcons.Application;
        ClientSize = new Size(590, 380);
        MinimumSize = new Size(420, 300);
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14), ColumnCount = 1, RowCount = 5 };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(new Label { Text = "DOI · arXiv · publisher URL", AutoSize = true });
        layout.Controls.Add(input);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        var settings = new Button { Text = "ADS Token…", AutoSize = true };
        var cancel = new Button { Text = "Cancel", AutoSize = true };
        buttons.Controls.AddRange([lookup, copy, settings, cancel]);
        layout.Controls.Add(buttons);
        layout.Controls.Add(status);
        layout.Controls.Add(output);
        Controls.Add(layout);
        AcceptButton = lookup;
        lookup.Click += async (_, _) => await Lookup();
        copy.Click += (_, _) => Copy();
        settings.Click += (_, _) => EditToken();
        cancel.Click += (_, _) => pending?.Cancel();
        FormClosing += (_, e) => { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
    }

    public void FocusInput() { input.Focus(); input.SelectAll(); }

    private async Task Lookup()
    {
        if (pending is not null) return;
        using var cancellation = new CancellationTokenSource();
        pending = cancellation;
        lookup.Enabled = false;
        status.Text = "Looking up citation…";
        try
        {
            var token = tokens.Load();
            var citation = await new CitationClient(http).LookupAsync(input.Text, token, cancellation.Token);
            if (IsDisposed) return;
            output.Text = citation.Bibtex;
            copy.Enabled = true;
            status.Text = $"Retrieved from {citation.Source}.";
            Copy();
        }
        catch (OperationCanceledException) { if (!IsDisposed) status.Text = "Lookup cancelled."; }
        catch (Exception e)
        {
            if (!IsDisposed) status.Text = e is CryptographicException or IOException or UnauthorizedAccessException
                ? "Could not read the saved token. Open ADS Token to replace or clear it."
                : e.Message;
        }
        finally { pending = null; if (!IsDisposed) lookup.Enabled = true; }
    }

    private void Copy()
    {
        try { Clipboard.SetText(output.Text); status.Text = "Copied BibTeX to clipboard."; }
        catch (ExternalException) { status.Text = "Citation ready. Clipboard is busy; click Copy to retry."; }
    }

    public void EditToken()
    {
        using var dialog = new Form { Text = "ADS API Token", ClientSize = new Size(470, 190), FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false, StartPosition = FormStartPosition.CenterParent };
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(12), RowCount = 3, ColumnCount = 1 };
        layout.Controls.Add(new Label { AutoSize = true, Text = "Saved once for your Windows account and reused by default.\nClear and save to remove. ADS_API_TOKEN remains a fallback.\nGet a token: ui.adsabs.harvard.edu/user/settings/token" });
        var field = new TextBox { Dock = DockStyle.Fill, UseSystemPasswordChar = true, AccessibleName = "ADS API token" };
        try { field.Text = tokens.Load() ?? ""; }
        catch (Exception e) when (e is CryptographicException or IOException or UnauthorizedAccessException) { }
        layout.Controls.Add(field);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        var save = new Button { Text = "Save", AutoSize = true };
        var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, AutoSize = true };
        buttons.Controls.AddRange([save, cancel]);
        layout.Controls.Add(buttons);
        save.Click += (_, _) =>
        {
            try { tokens.Save(field.Text); status.Text = field.Text.Trim().Length == 0 ? "Saved token cleared." : "ADS token saved as default."; dialog.Close(); }
            catch { MessageBox.Show(dialog, "Could not save the token. Check access to your local app data folder.", "BibGrab"); }
        };
        dialog.Controls.Add(layout);
        dialog.AcceptButton = save;
        dialog.CancelButton = cancel;
        dialog.ShowDialog(this);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { pending?.Cancel(); http.Dispose(); }
        base.Dispose(disposing);
    }
}
