using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace BibGrab;

public static class PaperInput
{
    public static string Normalize(string raw)
    {
        var value = raw.Trim();
        var arxiv = value;
        if (Uri.TryCreate(value, UriKind.Absolute, out var url) &&
            new[] { "arxiv.org", "www.arxiv.org", "export.arxiv.org" }.Contains(url.Host.ToLowerInvariant()))
            arxiv = Regex.Replace(url.AbsolutePath, @"^/(abs|pdf|html)/", "");
        arxiv = Regex.Replace(arxiv, "^arxiv:", "", RegexOptions.IgnoreCase);
        var id = Regex.Match(arxiv, @"^(\d{4}\.\d{4,5}|[a-zA-Z-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?(?:\.pdf)?/?$");
        if (id.Success) return "10.48550/arXiv." + id.Groups[1].Value;

        value = Uri.UnescapeDataString(value);
        var doi = Regex.Match(value, "10\\.\\d{4,9}/[^\\s\"<>]+").Value;
        doi = doi.Split('?', '#')[0];
        doi = Regex.Replace(doi, @"/(meta|pdf|fulltext|abstract|full|references|citations)/?$", "", RegexOptions.IgnoreCase);
        doi = doi.TrimEnd('/', '.', ',', ';');
        if (!Regex.IsMatch(doi, @"^10\.\d{4,9}/.+$"))
            throw new ArgumentException("Enter a DOI, publisher URL, or arXiv link.");
        return doi;
    }
}

public sealed record Citation(string Bibtex, string Source);

public sealed class CitationClient(HttpClient http)
{
    public async Task<Citation> LookupAsync(string input, string? token, CancellationToken cancellation = default)
    {
        var doi = PaperInput.Normalize(input);
        string? adsError = null;
        if (!string.IsNullOrWhiteSpace(token))
        {
            try { return new Citation(await AdsAsync(doi, token.Trim(), cancellation), "ADS"); }
            catch (Exception e) when (IsLookupFailure(e, cancellation)) { adsError = Describe(e); }
        }
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://doi.org/" + Uri.EscapeDataString(doi));
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/x-bibtex"));
            using var response = await http.SendAsync(request, cancellation);
            RequireSuccess(response, "DOI service");
            var text = (await response.Content.ReadAsStringAsync(cancellation)).Trim();
            RequireBibtex(text, "DOI service");
            return new Citation(text, "DOI service");
        }
        catch (Exception e) when (IsLookupFailure(e, cancellation))
        {
            throw new InvalidOperationException(adsError is null ? Describe(e) : $"ADS: {adsError}; DOI: {Describe(e)}");
        }
    }

    private async Task<string> AdsAsync(string doi, string token, CancellationToken cancellation)
    {
        const string prefix = "10.48550/arxiv.";
        var query = doi.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            ? $"identifier:\"arXiv:{doi[prefix.Length..]}\"" : $"doi:\"{doi}\"";
        using var request = new HttpRequestMessage(HttpMethod.Get,
            "https://api.adsabs.harvard.edu/v1/search/query?q=" + Uri.EscapeDataString(query) + "&fl=bibcode&rows=1");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        using var response = await http.SendAsync(request, cancellation);
        RequireSuccess(response, "ADS search");
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellation));
        var docs = json.RootElement.GetProperty("response").GetProperty("docs");
        if (docs.GetArrayLength() == 0) throw new InvalidOperationException("Paper not indexed in ADS.");
        var bibcode = docs[0].GetProperty("bibcode").GetString();
        if (string.IsNullOrWhiteSpace(bibcode)) throw new InvalidOperationException("ADS returned no bibcode.");

        using var export = new HttpRequestMessage(HttpMethod.Post, "https://api.adsabs.harvard.edu/v1/export/bibtex");
        export.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        export.Content = JsonContent.Create(new { bibcode = new[] { bibcode } });
        using var exported = await http.SendAsync(export, cancellation);
        RequireSuccess(exported, "ADS export");
        using var result = JsonDocument.Parse(await exported.Content.ReadAsStringAsync(cancellation));
        var text = result.RootElement.GetProperty("export").GetString()?.Trim() ?? "";
        RequireBibtex(text, "ADS export");
        return text;
    }

    private static bool IsLookupFailure(Exception e, CancellationToken cancellation) =>
        e is HttpRequestException or JsonException or KeyNotFoundException or InvalidOperationException ||
        (e is OperationCanceledException && !cancellation.IsCancellationRequested);

    private static string Describe(Exception e) => e switch
    {
        OperationCanceledException => "Request timed out. Check your connection and retry.",
        JsonException or KeyNotFoundException => "Service returned an unreadable response.",
        HttpRequestException => "Cannot reach the citation service. Check your connection or proxy.",
        _ => e.Message
    };

    private static void RequireSuccess(HttpResponseMessage response, string service)
    {
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"{service} HTTP {(int)response.StatusCode}" +
                ((int)response.StatusCode == 401 ? " (check the ADS token)." : "."));
    }

    private static void RequireBibtex(string text, string service)
    {
        if (!Regex.IsMatch(text, @"^@\w+\s*[{(]"))
            throw new InvalidOperationException($"{service} returned no valid BibTeX.");
    }
}
