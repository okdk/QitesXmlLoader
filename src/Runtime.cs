using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Threading;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace QitesXmlLoader {
 public sealed class NetworkState {public string Root,Error;public bool Connected;}
 public static class NetworkMemory {
  static readonly Dictionary<string,NetworkState> entries=new Dictionary<string,NetworkState>(StringComparer.OrdinalIgnoreCase);
  static readonly object gate=new object();
  public static NetworkState Get(string root){lock(gate){NetworkState value;return entries.TryGetValue(root,out value)?value:null;}}
  public static void Set(string root,bool connected,string error){lock(gate){entries[root]=new NetworkState{Root=root,Connected=connected,Error=error};}}
  public static NetworkState[] List(){lock(gate){var values=new NetworkState[entries.Count];entries.Values.CopyTo(values,0);return values;}}
  public static void Reset(){lock(gate){entries.Clear();}}
 }
 public sealed class Operation {
  public volatile bool PauseRequested, Paused;
  public volatile int Cancel; // 1: keep partial output; 2: rollback this operation
  public bool RollbackComplete=true;
  public string Stage=Text.Get("待機"), Detail="", Output="", JournalPath;
  public long Done, Total;
  public readonly object Gate=new object();
  public Operation() { JournalPath=Path.Combine(Path.GetTempPath(),"QitesXmlLoader-transaction-"+Guid.NewGuid().ToString("N")+".log"); }
  public void Report(string stage,long done,long total,string detail) {lock(Gate){Stage=stage;Done=done;Total=total;Detail=detail;}}
  public string[] Snapshot() {lock(Gate){return new[]{Stage,Done.ToString(),Total.ToString(),Detail,Output};}}
  public void Check() {try {while(PauseRequested && Cancel==0){Paused=true;Thread.Sleep(40);} if(Cancel!=0)throw new OperationCanceledException(Text.Get("処理を中止しました。"));}finally{Paused=false;}}
  readonly List<Created> created=new List<Created>();
  sealed class Created {public string Path,Id;public bool Directory;}
  void Remember(string path,bool directory) {
   var e=new Created{Path=Path.GetFullPath(path),Id=Native.Identity(path),Directory=directory};
   created.Add(e);
   File.AppendAllText(JournalPath,(directory?"D":"F")+"\t"+Convert.ToBase64String(Encoding.UTF8.GetBytes(e.Path))+"\t"+e.Id+Environment.NewLine,Encoding.UTF8);
  }
  public void MakeDirectory(string path) {
   path=Path.GetFullPath(path);Native.NoRedirect(path);
   if(Directory.Exists(path))return;
   string parent=Path.GetDirectoryName(path);if(!String.IsNullOrEmpty(parent))MakeDirectory(parent);
   if(Native.CreateDirectory(path,IntPtr.Zero))Remember(path,true);
   else if(!Directory.Exists(path))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  }
  public FileStream NewFile(string path) {
   Native.NoRedirect(path);var stream=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read);
   try { Remember(path,false);return stream; }catch {stream.Dispose();throw;}
  }
  public void WriteText(string path,string text) {using(var s=NewFile(path))using(var w=new StreamWriter(s,new UTF8Encoding(false))){w.Write(text);}}
  public void Publish(string partial,string output) { Check();Native.NoRedirect(partial);Native.NoRedirect(output);File.Move(partial,output);Remember(output,false); }
  public void Link(string source,string output) {
   Check();Native.NoRedirect(output);
   if(!Native.CreateHardLink(output,source,IntPtr.Zero))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   Remember(output,false);Check();
  }
  public string Rollback() {
   PauseRequested=false;Paused=false;var failures=new List<string>();
   for(int i=created.Count-1;i>=0;i--){var e=created[i];Report(Text.Get("復旧"),created.Count-i,created.Count,e.Path);
    try {if(!File.Exists(e.Path)&&!Directory.Exists(e.Path))continue;Native.NoRedirect(e.Path);
     if(Native.Identity(e.Path)!=e.Id)throw new IOException(Text.Get("作成時とファイルIDが異なります。"));
     if(e.Directory)Directory.Delete(e.Path,false);else File.Delete(e.Path);
    } catch(Exception ex){failures.Add(e.Path+": "+ex.Message);}
   }
   RollbackComplete=failures.Count==0;
   string result=RollbackComplete?Text.Get("処理開始前へ復旧しました。"):Text.Get("未復旧項目:\n")+String.Join("\n",failures.ToArray());
   File.AppendAllText(JournalPath,result+Environment.NewLine,Encoding.UTF8);return result;
  }
  public MemoryStream SnapshotXml(string path) {
   var info=new FileInfo(path);long length=info.Length;long stamp=info.LastWriteTimeUtc.Ticks;
   Report(Text.Get("1/4 XML容量確認"),0,length,"XML "+length.ToString("N0")+" bytes");Check();
   var memory=new MemoryStream();var buffer=new byte[1024*1024];long offset=0;
   try {while(offset<length){Check();int n;
     // No source XML handle remains open at a pause/cancel checkpoint.
     using(var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
      if(input.Length!=length||File.GetLastWriteTimeUtc(path).Ticks!=stamp)throw new IOException(Text.Get("読込中にXMLが変更されました。再実行してください。"));
      input.Position=offset;n=input.Read(buffer,0,(int)Math.Min(buffer.Length,length-offset));
     }
     if(n==0)throw new EndOfStreamException();memory.Write(buffer,0,n);offset+=n;
     Report(Text.Get("2/4 XML読込"),offset,length,"XML "+length.ToString("N0")+" bytes");
    }
    if(File.GetLastWriteTimeUtc(path).Ticks!=stamp)throw new IOException(Text.Get("読込中にXMLが変更されました。"));
    memory.Position=0;return memory;
   }catch{memory.Dispose();throw;}
  }
  public void Copy(string source,string output) {
   using(var input=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))
   using(var target=NewFile(output)){
    var buffer=new byte[1024*1024];long done=0;int n;
    while(true){Check();n=input.Read(buffer,0,buffer.Length);if(n==0)break;target.Write(buffer,0,n);done+=n;
     Report(Text.Get("書き出し・コピー"),done,input.Length,Path.GetFileName(source));}
   }Check();
  }
  public void Encode(string encoder,string[] arguments,string output) {
   using(var placeholder=NewFile(output)){} // Exclusively reserve and journal this new file.
   string identity=Native.Identity(output);
   var args=new List<string>(arguments);args.Add("-y");args.Add(output);
   var info=new ProcessStartInfo(encoder,Native.Arguments(args.ToArray()));info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
   using(var p=new Process()){
    p.StartInfo=info;p.Start();bool suspended=false;
    var error=p.StandardError.ReadToEndAsync();var stdout=p.StandardOutput.ReadToEndAsync();
    try {while(!p.WaitForExit(50)){
      if(Cancel!=0)throw new OperationCanceledException();
      if(PauseRequested&&!suspended){Native.Suspend(p);suspended=true;Paused=true;}
      if(!PauseRequested&&suspended){Native.Resume(p);suspended=false;Paused=false;}
     }
     stdout.GetAwaiter().GetResult();if(p.ExitCode!=0)throw new IOException(error.GetAwaiter().GetResult());
     if(Native.Identity(output)!=identity)throw new IOException(Text.Get("生成ファイルの同一性を確認できません。"));Check();
    }finally{if(suspended){Native.Resume(p);Paused=false;}if(!p.HasExited){p.Kill();p.WaitForExit();} }
   }
  }

 }
 public sealed class ProgressStream:Stream {
  readonly Stream inner;readonly Operation op;
  public ProgressStream(Stream stream,Operation operation){inner=stream;op=operation;}
  public override int Read(byte[] b,int o,int c){op.Check();int n=inner.Read(b,o,c);op.Report(Text.Get("3/4 XML走査"),inner.Position,inner.Length,Text.Get("全体 ")+inner.Length.ToString("N0")+Text.Get(" bytes / メモリー上のXMLを解析中"));return n;}
  public override bool CanRead{get{return true;}}public override bool CanWrite{get{return false;}}public override bool CanSeek{get{return false;}}
  public override long Length{get{return inner.Length;}}public override long Position{get{return inner.Position;}set{throw new NotSupportedException();}}
  public override void Flush(){}public override long Seek(long x,SeekOrigin y){throw new NotSupportedException();}public override void SetLength(long x){throw new NotSupportedException();}public override void Write(byte[] b,int o,int c){throw new NotSupportedException();}
 }
 public static class Native {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool CreateHardLink(string output,string source,IntPtr security);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool CreateDirectory(string path,IntPtr security);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sec,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle h,out FileInfoNative i);
  [StructLayout(LayoutKind.Sequential)]struct FileInfoNative{public uint Attr;public System.Runtime.InteropServices.ComTypes.FILETIME Creation,Access,Write;public uint Volume,SizeHi,SizeLo,Links,IndexHi,IndexLo;}
  [DllImport("ntdll.dll")]static extern int NtSuspendProcess(IntPtr h);
  [DllImport("ntdll.dll")]static extern int NtResumeProcess(IntPtr h);
  public static void Suspend(Process p){if(NtSuspendProcess(p.Handle)!=0)throw new IOException(Text.Get("一時停止に失敗しました。"));}
  public static void Resume(Process p){if(!p.HasExited&&NtResumeProcess(p.Handle)!=0)throw new IOException(Text.Get("再開に失敗しました。"));}
  public static string Identity(string path){using(var h=CreateFile(path,0,7,IntPtr.Zero,3,0x02000000|0x00200000,IntPtr.Zero)){FileInfoNative i;if(h.IsInvalid||!GetFileInformationByHandle(h,out i))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());return i.Volume.ToString("X8")+":"+i.IndexHi.ToString("X8")+i.IndexLo.ToString("X8");}}
  public static void NoRedirect(string path){string p=Path.GetFullPath(path);while(!String.IsNullOrEmpty(p)){if((File.Exists(p)||Directory.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException(Text.Get("再解析ポイントは使用できません: ")+p);p=Path.GetDirectoryName(p);}}
  public static string Arguments(string[] arguments){var result=new List<string>();foreach(string arg in arguments){var b=new StringBuilder("\"");int slashes=0;foreach(char c in arg){if(c=='\\'){slashes++;continue;}if(c=='\"')b.Append('\\',slashes*2+1);else b.Append('\\',slashes);slashes=0;b.Append(c);}b.Append('\\',slashes*2);b.Append('"');result.Add(b.ToString());}return String.Join(" ",result.ToArray());}
 }
}
