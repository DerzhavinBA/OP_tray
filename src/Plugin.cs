using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using OpenProjectTray;

class Plugin {
    readonly Dictionary<string,ButtonSettings> buttons = new Dictionary<string,ButtonSettings>();
    readonly Dictionary<string,string> rendered = new Dictionary<string,string>();
    readonly Dictionary<string,string> images = new Dictionary<string,string>();
    readonly object gate = new object();
    readonly SemaphoreSlim sendGate = new SemaphoreSlim(1,1);
    readonly SemaphoreSlim paintGate = new SemaphoreSlim(1,1);
    readonly string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,".."));
    ClientWebSocket socket;
    string state = "Offline", defaultExe = "";
    int activating;
    static Dictionary<string,object> Map(object obj) { return obj as Dictionary<string,object> ?? new Dictionary<string,object>(); }
    static object Get(Dictionary<string,object> map,string key) { object value; return map.TryGetValue(key,out value) ? value : null; }
    static string Str(Dictionary<string,object> map,string key) { return Convert.ToString(Get(map,key)); }
    static string Json(object value) { return new JavaScriptSerializer().Serialize(value); }
    static void Log(Exception e) {
        try { string dir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"OpenProjectTray"); Directory.CreateDirectory(dir); File.AppendAllText(Path.Combine(dir,"streamdock.log"),DateTime.Now.ToString("s")+" "+e.Message+Environment.NewLine); } catch { }
    }
    async Task Send(object value) {
        byte[] data=Encoding.UTF8.GetBytes(Json(value));
        await sendGate.WaitAsync();
        try { using(var timeout=new CancellationTokenSource(5000)) await socket.SendAsync(new ArraySegment<byte>(data),WebSocketMessageType.Text,true,timeout.Token); }
        finally { sendGate.Release(); }
    }
    string Exe(ButtonSettings settings) {
        string path = String.IsNullOrWhiteSpace(settings.ExePath) ? defaultExe : settings.ExePath;
        if(String.IsNullOrWhiteSpace(path)) path=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs/OpenProjectTray/OpenProjectTray.exe");
        if(!File.Exists(path)) throw new FileNotFoundException("Укажите путь к OpenProjectTray.exe в настройках кнопки",path);
        return Path.GetFullPath(path);
    }
    void StartController(ButtonSettings settings) {
        var info=new ProcessStartInfo(Exe(settings),"--background");
        info.UseShellExecute=false; info.CreateNoWindow=true; info.WindowStyle=ProcessWindowStyle.Hidden;
        using(var process=Process.Start(info)) { }
    }
    async Task Activate(string context,ButtonSettings settings) {
        if(Interlocked.CompareExchange(ref activating,1,0)!=0) return;
        bool failed = false;
        try {
            await Task.Run(() => {
                bool connected=false;
                try { BridgeClient.Request("status"); connected=true; } catch { }
                if(!connected) {
                    StartController(settings);
                    for(int i=0;i<30;i++) { Thread.Sleep(250); try { BridgeClient.Request("status"); connected=true; break; } catch { } }
                    if(!connected) throw new IOException("Контроллер не отвечает");
                    // First press on a black indicator opens only the application.
                    return;
                }
                string reply=BridgeClient.Request("activate"); // no retry on ambiguous outcome
                var status=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(reply);
                if(Str(status,"result")=="accepted") { lock(gate) state="Starting"; }
            });
        } catch(Exception e) {
            Log(e); lock(gate) state="Error";
            failed = true;
        } finally { Interlocked.Exchange(ref activating,0); }
        if(failed) await Send(new { @event="showAlert",context=context });
        await Paint();
    }
    async Task Paint() {
        await paintGate.WaitAsync();
        try {
        List<KeyValuePair<string,ButtonSettings>> snapshot; string current;
        lock(gate) { snapshot=new List<KeyValuePair<string,ButtonSettings>>(buttons); current=state; }
        foreach(var entry in snapshot) {
            int frame=entry.Value.IconStyle=="orbit" ? (int)((DateTime.UtcNow.Ticks/TimeSpan.TicksPerMillisecond/125)%24) : 0;
            string key=current+":"+entry.Value.VisualKey+":"+frame;
            lock(gate) { string old; if(rendered.TryGetValue(entry.Key,out old) && old==key) continue; }
            string image;
            if(!images.TryGetValue(key,out image)) {
                image=ButtonRenderer.DataUrl(Path.Combine(root,"static/OpenProject.ico"),current,entry.Value,frame);
                if(images.Count>=256) images.Clear();
                images[key]=image;
            }
            await Send(new { @event="setImage", context=entry.Key, payload=new { image=image,target=0 } });
            lock(gate) rendered[entry.Key]=key;
        }
        } finally { paintGate.Release(); }
    }
    async Task Animate(CancellationToken cancellation) {
        while(!cancellation.IsCancellationRequested && socket.State==WebSocketState.Open) {
            await Paint(); await Task.Delay(125,cancellation);
        }
    }
    async Task Poll(CancellationToken cancellation) {
        while(!cancellation.IsCancellationRequested && socket.State==WebSocketState.Open) {
            try {
                string raw=await Task.Run(()=>BridgeClient.Request("status"));
                var status=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(raw);
                lock(gate) state=ButtonSettings.DisplayState(Str(status,"state"),Convert.ToBoolean(Get(status,"busy") ?? false));
            } catch(TimeoutException) {
                lock(gate) state="Offline";
            } catch(Exception) {
                lock(gate) state="Error";
            }
            await Paint();
            await Task.Delay(1000,cancellation);
        }
    }
    async Task Run(string[] args) {
        var cli=new Dictionary<string,string>();
        for(int i=0;i+1<args.Length;i+=2) cli[args[i]]=args[i+1];
        int port; if(!cli.ContainsKey("-port") || !Int32.TryParse(cli["-port"],out port) || port<1 || port>65535) throw new ArgumentException("StreamDock must launch this plugin");
        string config=Path.Combine(root,"connection.json");
        if(File.Exists(config)) defaultExe=ButtonSettings.Parse(File.ReadAllText(config)).ExePath;
        while(true) {
            using(socket=new ClientWebSocket()) using(var stop=new CancellationTokenSource()) {
                Task polling=null, animation=null;
                try {
                    using(var timeout=new CancellationTokenSource(5000)) await socket.ConnectAsync(new Uri("ws://127.0.0.1:"+port),timeout.Token);
                    await Send(new { @event=cli["-registerEvent"],uuid=cli["-pluginUUID"] });
                    lock(gate) { buttons.Clear(); rendered.Clear(); }
                    polling=Poll(stop.Token);
                    animation=Animate(stop.Token);
                    var animationWatcher=animation.ContinueWith(t=>{if(t.IsFaulted) socket.Abort();},TaskScheduler.Default);
                    // Observe poll failure by aborting the receive; reconnect below.
                    var watcher=polling.ContinueWith(t=>{ if(t.IsFaulted) socket.Abort(); },TaskScheduler.Default);
                    var buffer=new byte[8192];
                    while(socket.State==WebSocketState.Open) {
                        using(var message=new MemoryStream()) {
                            WebSocketReceiveResult chunk;
                            do {
                                chunk=await socket.ReceiveAsync(new ArraySegment<byte>(buffer),stop.Token);
                                if(chunk.MessageType==WebSocketMessageType.Close) throw new IOException("StreamDock closed connection");
                                message.Write(buffer,0,chunk.Count);
                                if(message.Length>1024*1024) throw new IOException("Oversized WebSocket message");
                            } while(!chunk.EndOfMessage);
                            var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(message.ToArray()));
                            string evt=Str(data,"event").TrimStart('_'), context=Str(data,"context");
                            var payload=Map(Get(data,"payload"));
                            if(evt=="willAppear" || evt=="didReceiveSettings") {
                                if(evt=="didReceiveSettings") { lock(gate) { if(!buttons.ContainsKey(context)) continue; } }
                                var settings=ButtonSettings.Parse(Json(Get(payload,"settings") ?? new Dictionary<string,object>()));
                                lock(gate) { buttons[context]=settings; rendered.Remove(context); }
                                await Paint();
                            } else if(evt=="willDisappear") {
                                lock(gate) { buttons.Remove(context); rendered.Remove(context); }
                            } else if(evt=="keyDown") {
                                ButtonSettings settings; lock(gate) { if(!buttons.TryGetValue(context,out settings)) settings=new ButtonSettings(); }
                                // Keep receive responsive while the controller starts.
                                var activation=Activate(context,settings);
                                var observe=activation.ContinueWith(t=>{if(t.IsFaulted) Log(t.Exception);},TaskScheduler.Default);
                            }
                        }
                    }
                } catch(Exception e) { Log(e); }
                finally { stop.Cancel(); socket.Abort(); }
                if(polling!=null) { try { await polling; } catch { } }
                if(animation!=null) { try { await animation; } catch { } }
            }
            await Task.Delay(2000);
        }
    }
    static int Main(string[] args) { try { new Plugin().Run(args).GetAwaiter().GetResult(); return 0; } catch(Exception e) { Log(e); return 1; } }
}
