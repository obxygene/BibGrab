using System.Net;
using System.Text;
using BibGrab;

static void Check(bool condition, string description)
{
    if (!condition) throw new Exception(description);
}

const string doi = "10.1103/PhysRev.47.777";
Check(PaperInput.Normalize("https://doi.org/" + doi) == doi, "DOI URL");
Check(PaperInput.Normalize("https://journals.aps.org/pr/abstract/" + doi + "?source=test") == doi, "Publisher URL");
foreach (var input in new[] { "0709.2140", "arXiv:0709.2140", "https://arxiv.org/pdf/0709.2140v2.pdf" })
    Check(PaperInput.Normalize(input) == "10.48550/arXiv.0709.2140", "Modern arXiv normalization");
Check(PaperInput.Normalize("https://arxiv.org/abs/hep-th/9711200v3") == "10.48550/arXiv.hep-th/9711200", "Legacy arXiv normalization");
try { PaperInput.Normalize("https://example.org/abs/0709.2140"); throw new Exception("Invalid input accepted"); }
catch (ArgumentException) { }

const string bibtex = "@article{Einstein1935, title={Example}}";
var ads = new Stub(async (request, number) =>
{
    Check(request.Headers.Authorization?.Parameter == "test-token", "ADS authentication");
    if (number == 1)
    {
        Check(Uri.UnescapeDataString(request.RequestUri!.Query).Contains("identifier:\"arXiv:hep-th/9711200\""), "arXiv identifier query");
        return Reply(HttpStatusCode.OK, "{\"response\":{\"docs\":[{\"bibcode\":\"sample\"}]}}");
    }
    Check(request.Method == HttpMethod.Post, "Export is POST");
    Check((await request.Content!.ReadAsStringAsync()).Contains("sample"), "Export bibcode");
    return Reply(HttpStatusCode.OK, "{\"export\":\"" + bibtex + "\"}");
});
using (var http = new HttpClient(ads))
{
    var result = await new CitationClient(http).LookupAsync("hep-th/9711200", "test-token");
    Check(result.Bibtex == bibtex && result.Source == "ADS" && ads.Count == 2, "ADS search and export");
}

var fallback = new Stub((request, number) =>
{
    if (number == 1) return Task.FromResult(Reply(HttpStatusCode.BadRequest, "{}"));
    Check(request.RequestUri!.Host == "doi.org", "DOI fallback host");
    Check(request.Headers.Authorization is null, "Never send ADS token to DOI service");
    Check(request.Headers.Accept.ToString() == "application/x-bibtex", "Content negotiation header");
    return Task.FromResult(Reply(HttpStatusCode.OK, bibtex));
});
using (var http = new HttpClient(fallback))
    Check((await new CitationClient(http).LookupAsync(doi, "test-token")).Source == "DOI service", "Fallback after HTTP 400");

using (var http = new HttpClient(new Stub((_, _) => Task.FromResult(Reply(HttpStatusCode.BadRequest, "{}")))))
{
    try { await new CitationClient(http).LookupAsync(doi, "test-token"); throw new Exception("Expected failure"); }
    catch (InvalidOperationException e) { Check(e.Message.Contains("ADS") && e.Message.Contains("DOI") && e.Message.Contains("400"), "Both errors retained"); }
}
using (var http = new HttpClient(new Stub((_, _) => Task.FromResult(Reply(HttpStatusCode.OK, "<html>not a citation</html>")))))
{
    try { await new CitationClient(http).LookupAsync(doi, null); throw new Exception("HTML accepted"); }
    catch (InvalidOperationException e) { Check(e.Message.Contains("BibTeX"), "Reject invalid citation"); }
}
using (var cancel = new CancellationTokenSource())
using (var http = new HttpClient(new Stub((_, _) => throw new OperationCanceledException(cancel.Token))))
{
    cancel.Cancel();
    try { await new CitationClient(http).LookupAsync(doi, "test-token", cancel.Token); throw new Exception("Cancellation ignored"); }
    catch (OperationCanceledException) { }
}
Console.WriteLine("All citation parsing, ADS, fallback, authentication isolation, and cancellation checks passed.");

static HttpResponseMessage Reply(HttpStatusCode code, string content) => new(code)
{ Content = new StringContent(content, Encoding.UTF8) };

sealed class Stub(Func<HttpRequestMessage, int, Task<HttpResponseMessage>> reply) : HttpMessageHandler
{
    public int Count { get; private set; }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return reply(request, ++Count);
    }
}
