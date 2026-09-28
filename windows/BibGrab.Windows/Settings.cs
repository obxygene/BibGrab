using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace BibGrab;

internal sealed class TokenStore
{
    private readonly string path;
    public TokenStore(string? directory = null) => path = Path.Combine(directory ??
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BibGrab"), "ads-token.dat");

    public string? Load()
    {
        if (File.Exists(path))
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser));
        return Environment.GetEnvironmentVariable("ADS_API_TOKEN")?.Trim();
    }

    public void Save(string value)
    {
        value = value.Trim();
        if (value.Length == 0) { File.Delete(path); return; }
        var encrypted = ProtectedData.Protect(Encoding.UTF8.GetBytes(value), null, DataProtectionScope.CurrentUser);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        try
        {
            File.WriteAllBytes(temporary, encrypted);
            File.Move(temporary, path, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

internal static class Startup
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public static bool Enabled
    {
        get { using var key = Registry.CurrentUser.OpenSubKey(Key); return key?.GetValue("BibGrab") is string; }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(Key);
            if (value) key.SetValue("BibGrab", $"\"{Application.ExecutablePath}\" --background");
            else key.DeleteValue("BibGrab", throwOnMissingValue: false);
        }
    }
}
