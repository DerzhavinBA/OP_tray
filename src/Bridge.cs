using System;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace OpenProjectTray {
    public static class ActivationPolicy {
        public static string Action(bool running, bool busy) { return busy ? "" : running ? "restart-migrate" : "start"; }
    }
    public static class BridgeClient {
        public static string PipeName { get { return "OpenProjectTray." + WindowsIdentity.GetCurrent().User.Value; } }
        public static string Request(string command) { return Request(PipeName, command, 1500); }
        public static string Request(string pipeName, string command, int timeout) {
            using (var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous)) {
                pipe.Connect(timeout);
                var data = Encoding.UTF8.GetBytes(command + "\n");
                var write = pipe.WriteAsync(data, 0, data.Length);
                if (!write.Wait(timeout)) throw new IOException("Controller write timeout");
                var reader = new StreamReader(pipe, Encoding.UTF8);
                var read = reader.ReadLineAsync();
                if (!read.Wait(timeout)) throw new IOException("Controller response timeout; command will not be retried");
                if (read.Result == null) throw new IOException("Controller disconnected");
                return read.Result;
            }
        }
    }
    public sealed class BridgeServer : IDisposable {
        readonly object gate = new object();
        readonly string name;
        readonly Thread worker;
        NamedPipeServerStream active;
        volatile bool stopping;
        bool pending, busy;
        string state = "Stopped", operation = "", error = "";
        DateTime updated = DateTime.UtcNow;
        public string LastFailure { get; private set; }
        public BridgeServer() : this(BridgeClient.PipeName) { }
        public BridgeServer(string pipeName) { name = pipeName; worker = new Thread(Serve); worker.IsBackground = true; worker.Start(); }
        public void Publish(string value, bool isBusy, string action, string lastError) {
            lock(gate) { state = value; busy = isBusy; operation = action ?? ""; error = lastError ?? ""; updated = DateTime.UtcNow; }
        }
        public bool TakeActivation() { lock(gate) { if (!pending) return false; pending = false; busy = true; return true; } }
        string Reply(string command) {
            lock(gate) {
                string result = "ok";
                bool stale = (DateTime.UtcNow - updated).TotalSeconds > 5;
                if (command == "activate") {
                    if (busy || pending || stale) result = "busy";
                    else { pending = true; result = "accepted"; }
                } else if (command != "status") result = "invalid";
                return new JavaScriptSerializer().Serialize(new { result = result, state = stale ? "Error" : state, busy = busy || pending, operation = operation, error = stale ? "Controller is not responding" : error });
            }
        }
        void Serve() {
            while (!stopping) {
                try {
                    var security = new PipeSecurity();
                    security.SetAccessRuleProtection(true, false);
                    security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
                    using (var pipe = new NamedPipeServerStream(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 4096, 4096, security)) {
                        lock(gate) { if (stopping) return; active = pipe; }
                        pipe.WaitForConnection();
                        var reader = new StreamReader(pipe, Encoding.UTF8);
                        // Bound reads so a broken local client cannot monopolize the pipe.
                        var command = new StringBuilder();
                        var character = new char[1];
                        while (command.Length < 32) {
                            var read = reader.ReadAsync(character, 0, 1);
                            if (!read.Wait(1500) || read.Result == 0) throw new IOException("Incomplete command");
                            if (character[0] == '\n') break;
                            command.Append(character[0]);
                        }
                        byte[] bytes = Encoding.UTF8.GetBytes(Reply(command.ToString().Trim()) + "\n");
                        if (!pipe.WriteAsync(bytes, 0, bytes.Length).Wait(1500)) throw new IOException("Response timeout");
                    }
                } catch (Exception e) { LastFailure = e.ToString(); if (!stopping) Thread.Sleep(30); }
                finally { lock(gate) active = null; }
            }
        }
        public void Dispose() { stopping = true; lock(gate) { if (active != null) active.Dispose(); } worker.Join(2000); }
    }
}
