using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

internal static class NodeReplProxy
{
    private const string ProxyUrl = "http://127.0.0.1:7890";

    private static int Main(string[] args)
    {
        try
        {
            string node = Environment.GetEnvironmentVariable("NODE_REPL_NODE_PATH");
            if (String.IsNullOrEmpty(node) || !Path.IsPathRooted(node))
                throw new InvalidOperationException("Codex did not supply an absolute NODE_REPL_NODE_PATH.");

            // Codex stages node.exe and node_repl.exe together, including after updates.
            string executable = Path.Combine(Path.GetDirectoryName(node), "node_repl.exe");
            if (!File.Exists(executable))
                throw new FileNotFoundException("Could not find Codex's bundled node_repl.exe.", executable);

            var start = new ProcessStartInfo(executable, String.Join(" ", Array.ConvertAll(args, QuoteArgument)));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            // Inherit stdin directly. .NET Framework's redirected input writer may prepend a BOM.
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            SetProxyForBrowser(start);

            using (Process child = Process.Start(start))
            {
                Task stdout = child.StandardOutput.BaseStream.CopyToAsync(Console.OpenStandardOutput());
                Task stderr = child.StandardError.BaseStream.CopyToAsync(Console.OpenStandardError());
                child.WaitForExit();
                Task.WaitAll(stdout, stderr);
                return child.ExitCode;
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("codex-cua-clash: " + error.Message);
            return 1;
        }
    }

    private static void SetProxyForBrowser(ProcessStartInfo start)
    {
        var env = start.EnvironmentVariables;
        string surfaces = env["CUA_REPL_ENABLED_SURFACES"] ?? "";
        if (!("," + surfaces + ",").Contains(",browser,"))
            return;

        // Windows environment names are case-insensitive.
        string bypass = env["NO_PROXY"];
        env["NO_PROXY"] = (String.IsNullOrEmpty(bypass) ? "" : bypass + ",") + "localhost,127.0.0.1,::1,[::1]";
        env["HTTPS_PROXY"] = ProxyUrl;
        env["NODE_USE_ENV_PROXY"] = "1";
        string allowlist = env["NODE_REPL_UNTRUSTED_ENV_ALLOWLIST"];
        env["NODE_REPL_UNTRUSTED_ENV_ALLOWLIST"] = (String.IsNullOrEmpty(allowlist) ? "" : allowlist + ",")
            + "HTTPS_PROXY,https_proxy,NO_PROXY,no_proxy,NODE_USE_ENV_PROXY";
    }

    private static string QuoteArgument(string argument)
    {
        // Windows doubles backslashes before a quote and before the closing quote.
        return "\"" + Regex.Replace(argument, @"(\\*)(""|\z)", match =>
            match.Groups[1].Value + match.Groups[1].Value +
            (match.Groups[2].Length == 0 ? "" : "\\\"")) + "\"";
    }
}
