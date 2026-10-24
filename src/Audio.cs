using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Collections.Generic;
using NAudio.CoreAudioApi;
using NAudio.Wave;
namespace QitesXmlLoader {
 public sealed class OutputDevice {public string Id{get;set;}public string Name{get;set;}}
 public sealed class AudioEngine:IDisposable {
  public static OutputDevice[] Devices(){var list=new List<OutputDevice>();list.Add(new OutputDevice{Id="",Name=Text.Get("Windowsの既定デバイス")});using(var e=new MMDeviceEnumerator()){foreach(var d in e.EnumerateAudioEndPoints(DataFlow.Render,DeviceState.Active)){list.Add(new OutputDevice{Id=d.ID,Name=d.FriendlyName});d.Dispose();}}return list.ToArray();}
  public volatile bool Finished,Paused;
  public volatile float SignalPeak,DevicePeak;
  public string Error="",DeviceName="",DeviceId="";
  public int DecoderExitCode;
  long decoded;public long DecodedBytes{get{return Interlocked.Read(ref decoded);}}
  double positionSeconds,durationSeconds;
  public double PositionSeconds{get{return Interlocked.CompareExchange(ref positionSeconds,0,0);}}
  public double DurationSeconds{get{return Interlocked.CompareExchange(ref durationSeconds,0,0);}}
  volatile bool stopped;Thread thread;Process decoder;WasapiOut output;
  readonly string path,device,encoder;readonly double offset;
  public AudioEngine(string path,string device,string encoder):this(path,device,encoder,0,0){}
  public AudioEngine(string path,string device,string encoder,double startSeconds,double totalSeconds){this.path=path;this.device=device;this.encoder=encoder;offset=Math.Max(0,startSeconds);positionSeconds=offset;durationSeconds=Math.Max(0,totalSeconds);thread=new Thread(Pump);thread.IsBackground=true;thread.Name="QitesXmlLoader audio";thread.SetApartmentState(ApartmentState.MTA);thread.Start();}
  void Pump(){MMDevice endpoint=null;MMDeviceEnumerator enumerator=null;
   try {
    if(stopped)return;enumerator=new MMDeviceEnumerator();endpoint=String.IsNullOrEmpty(device)?enumerator.GetDefaultAudioEndpoint(DataFlow.Render,Role.Multimedia):enumerator.GetDevice(device);
    DeviceName=endpoint.FriendlyName;DeviceId=endpoint.ID;
    if(String.IsNullOrEmpty(encoder)){
     using(WaveStream reader=System.IO.Path.GetExtension(path).Equals(".wav",StringComparison.OrdinalIgnoreCase)?(WaveStream)new WaveFileReader(path):new MediaFoundationReader(path)){
      Interlocked.Exchange(ref durationSeconds,reader.TotalTime.TotalSeconds);
      reader.CurrentTime=TimeSpan.FromSeconds(Math.Min(offset,reader.TotalTime.TotalSeconds));
      output=new WasapiOut(endpoint,AudioClientShareMode.Shared,true,100);output.Init(reader);output.Volume=0.5f;
      output.PlaybackStopped+=(s,e)=>{if(e.Exception!=null){Error=e.Exception.ToString();stopped=true;}};
      if(stopped)return;output.Play();if(Paused)output.Pause();
      while(!stopped&&output.PlaybackState!=PlaybackState.Stopped){Interlocked.Exchange(ref decoded,reader.Position);Meter(endpoint);Thread.Sleep(20);}
      Interlocked.Exchange(ref decoded,reader.Position);
     }
     return;
    }
    var wave=new BufferedWaveProvider(new WaveFormat(48000,16,2)){BufferDuration=TimeSpan.FromSeconds(2),ReadFully=true,DiscardOnBufferOverflow=false};
    output=new WasapiOut(endpoint,AudioClientShareMode.Shared,true,100);output.Init(wave);
    output.PlaybackStopped+=(s,e)=>{if(e.Exception!=null){Error=e.Exception.ToString();stopped=true;}};
    var info=new ProcessStartInfo(encoder,Native.Arguments(new[]{"-hide_banner","-nostdin","-v","error","-protocol_whitelist","file,pipe","-ss",offset.ToString("0.######",System.Globalization.CultureInfo.InvariantCulture),"-i",path,"-map","0:a:0","-vn","-af","volume=0.5","-ac","2","-ar","48000","-f","s16le","pipe:1"}));
    info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
    decoder=new Process{StartInfo=info};if(stopped)return;decoder.Start();var error=decoder.StandardError.ReadToEndAsync();
    var buffer=new byte[8192];bool started=false;
    while(!stopped){
     if(Paused){Meter(endpoint);Thread.Sleep(20);continue;}
     if(wave.BufferLength-wave.BufferedBytes<buffer.Length){Meter(endpoint);Thread.Sleep(10);continue;}
     int n=decoder.StandardOutput.BaseStream.Read(buffer,0,buffer.Length);if(n==0)break;
     wave.AddSamples(buffer,0,n);Interlocked.Add(ref decoded,n);
     float peak=0;for(int i=0;i+1<n;i+=2){float v=Math.Abs((short)(buffer[i]|(buffer[i+1]<<8))/32768f);if(v>peak)peak=v;}SignalPeak=peak;
     if(!started){output.Play();started=true;if(Paused)output.Pause();}Meter(endpoint);
    }
    if(!stopped){decoder.WaitForExit();DecoderExitCode=decoder.ExitCode;if(DecoderExitCode!=0)Error=error.GetAwaiter().GetResult();
     while(!stopped&&wave.BufferedBytes>0){Meter(endpoint);Thread.Sleep(20);}
    }
   }catch(Exception e){if(!stopped)Error=e.ToString();}
   finally {
    try{if(decoder!=null){try{if(!decoder.HasExited){decoder.Kill();decoder.WaitForExit();}}catch(InvalidOperationException){}decoder.Dispose();}}catch(Exception e){Error+=e.Message;}
    try{if(output!=null){output.Stop();output.Dispose();}}catch(Exception e){Error+=e.Message;}
    if(endpoint!=null)endpoint.Dispose();if(enumerator!=null)enumerator.Dispose();Finished=true;
   }
  }
  void Meter(MMDevice endpoint){try{DevicePeak=endpoint.AudioMeterInformation.MasterPeakValue;if(output!=null){double seconds=offset+(double)output.GetPosition()/output.OutputWaveFormat.AverageBytesPerSecond;if(DurationSeconds>0)seconds=Math.Min(seconds,DurationSeconds);Interlocked.Exchange(ref positionSeconds,seconds);}}catch{}}
  public void SetPaused(bool value){Paused=value;var current=output;if(current!=null){if(value)current.Pause();else current.Play();}}
  public void Dispose(){stopped=true;Paused=false;var p=decoder;if(p!=null){try{if(!p.HasExited)p.Kill();}catch(InvalidOperationException){}}
   if(thread!=null&&!thread.Join(5000))Error=Text.Get("音声処理の終了待ちがタイムアウトしました。");
  }
 }
}
