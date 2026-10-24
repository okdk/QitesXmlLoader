using System;
using System.IO;
using System.Xml;
using System.Text;
using System.Security.Cryptography;
using System.Collections;
using System.Collections.Generic;
using System.Web.Script.Serialization;
namespace QitesXmlLoader {
 public sealed class XmlSnapshot {
  public string Path,Hash,CachePath,Summary;
  public long Length,Ticks;
  public Dictionary<string,object> Tracks=new Dictionary<string,object>();
  public List<object> Playlists=new List<object>();
  public Dictionary<string,string> TrackHashes=new Dictionary<string,string>();
  public List<string> PlaylistHashes=new List<string>();
  public Dictionary<string,object> Library(){return new Dictionary<string,object>{{"Tracks",Tracks},{"Playlists",Playlists}};}
 }
 public static class XmlCache {
  static JavaScriptSerializer Serializer(){return new JavaScriptSerializer{MaxJsonLength=Int32.MaxValue,RecursionLimit=128};}
  static string Hash(string text){using(var sha=SHA256.Create()){return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-","");}}
  static Dictionary<string,object> Dict(object value){return (Dictionary<string,object>)value;}
  static object Node(XmlNode node,Operation op,int depth=0){op.Check();if(depth>128)throw new InvalidDataException(Text.Get("XMLの階層が深すぎます。"));switch(node.LocalName){
   case "dict":var dict=new Dictionary<string,object>();var nodes=new List<XmlNode>();foreach(XmlNode n in node.ChildNodes)if(n.NodeType==XmlNodeType.Element)nodes.Add(n);
    for(int i=0;i<nodes.Count;i+=2){if(nodes[i].LocalName!="key"||i+1>=nodes.Count)throw new InvalidDataException(Text.Get("不正なplist辞書"));dict[nodes[i].InnerText]=Node(nodes[i+1],op,depth+1);}return dict;
   case "array":var list=new List<object>();foreach(XmlNode n in node.ChildNodes)if(n.NodeType==XmlNodeType.Element)list.Add(Node(n,op,depth+1));return list.ToArray();
   case "true":return true;case "false":return false;case "integer":return Int64.Parse(node.InnerText);default:return node.InnerText;
  }}
  static object Decode(string raw,Operation op){var doc=new XmlDocument();doc.XmlResolver=null;doc.LoadXml(raw);return Node(doc.DocumentElement,op);}
  public static XmlSnapshot Load(string path,Operation op){
   var json=Serializer();var result=new XmlSnapshot();result.CachePath=path;
   using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))using(var r=new StreamReader(f,Encoding.UTF8)){
    if(r.ReadLine()!="QitesXmlLoader-cache-v1")throw new InvalidDataException(Text.Get("キャッシュ形式が違います。"));
    var header=Dict(json.DeserializeObject(r.ReadLine()));result.Path=(string)header["Path"];result.Hash=(string)header["Hash"];result.Length=Convert.ToInt64(header["Length"]);result.Ticks=Convert.ToInt64(header["Ticks"]);
    long total=Convert.ToInt64(header["Count"]),done=0;string line;
    while((line=r.ReadLine())!=null){op.Check();var fields=line.Split(new[]{'\t'},4);
     if(fields[0]=="T"){result.TrackHashes[fields[1]]=fields[2];result.Tracks[fields[1]]=json.DeserializeObject(fields[3]);}
     else if(fields[0]=="P"){result.PlaylistHashes.Add(fields[1]);result.Playlists.Add(json.DeserializeObject(fields[2]));}
     else throw new InvalidDataException(Text.Get("キャッシュレコードが不正です。"));
     done++;op.Report(Text.Get("キャッシュ高速読込"),done,total,result.Path);
    }
    if(done!=total)throw new InvalidDataException(Text.Get("キャッシュが不完全です。"));
   }
   result.Summary=Text.Get("キャッシュから復元（元XML更新確認待ち）");return result;
  }
  public static void Save(XmlSnapshot snapshot,string directory,Operation op){
   op.MakeDirectory(directory);string file=System.IO.Path.Combine(directory,DateTime.UtcNow.ToString("yyyyMMddHHmmssfffffff")+"-"+Guid.NewGuid().ToString("N")+".cache");
   var json=Serializer();long total=snapshot.Tracks.Count+snapshot.Playlists.Count,done=0;
   // Publish by renaming only after the whole cache has been flushed.
   string partial=file+".partial";
   using(var f=op.NewFile(partial))using(var w=new StreamWriter(f,new UTF8Encoding(false))){
    w.WriteLine("QitesXmlLoader-cache-v1");w.WriteLine(json.Serialize(new{snapshot.Path,snapshot.Hash,snapshot.Length,snapshot.Ticks,Count=total}));
    foreach(var entry in snapshot.Tracks){op.Check();w.WriteLine("T\t"+entry.Key+"\t"+snapshot.TrackHashes[entry.Key]+"\t"+json.Serialize(entry.Value));op.Report(Text.Get("キャッシュ保存"),++done,total,snapshot.Path);}
    for(int i=0;i<snapshot.Playlists.Count;i++){op.Check();w.WriteLine("P\t"+snapshot.PlaylistHashes[i]+"\t"+json.Serialize(snapshot.Playlists[i]));op.Report(Text.Get("キャッシュ保存"),++done,total,snapshot.Path);}
   }
   op.Publish(partial,file);snapshot.CachePath=file;
  }
  public static XmlSnapshot Read(string path,XmlSnapshot previous,Operation op){
   using(var memory=op.SnapshotXml(path)){
    string fileHash;using(var sha=SHA256.Create()){
     var buffer=new byte[1024*1024];int n;
     while((n=memory.Read(buffer,0,buffer.Length))>0){op.Check();sha.TransformBlock(buffer,0,n,buffer,0);op.Report(Text.Get("XML更新確認・SHA256"),memory.Position,memory.Length,Text.Get("全体 ")+memory.Length.ToString("N0")+" bytes");}
     sha.TransformFinalBlock(buffer,0,0);fileHash=BitConverter.ToString(sha.Hash).Replace("-","");
    }memory.Position=0;op.Check();
    if(previous!=null&&String.Equals(System.IO.Path.GetFullPath(path),previous.Path,StringComparison.OrdinalIgnoreCase)&&fileHash==previous.Hash){previous.Summary=Text.Get("XML内容変更なし（SHA256照合済み）");return previous;}
    // Validate depth iteratively before ReadOuterXml/DOM conversion can recurse.
    var depthSettings=new XmlReaderSettings{DtdProcessing=DtdProcessing.Ignore,XmlResolver=null,IgnoreWhitespace=true,CloseInput=false};
    using(var depthReader=XmlReader.Create(memory,depthSettings)){
     int nodes=0;while(depthReader.Read()){op.Check();if(depthReader.Depth>128)throw new InvalidDataException(Text.Get("XMLの階層が深すぎます。"));if(++nodes%256==0)op.Report(Text.Get("XML構造・深さ確認"),memory.Position,memory.Length,"XML");}
    }memory.Position=0;
    var result=new XmlSnapshot{Path=System.IO.Path.GetFullPath(path),Hash=fileHash,Length=memory.Length,Ticks=File.GetLastWriteTimeUtc(path).Ticks};
    var oldLists=new Dictionary<string,object>();if(previous!=null)for(int i=0;i<previous.PlaylistHashes.Count;i++)oldLists[previous.PlaylistHashes[i]]=previous.Playlists[i];
    int reuseTracks=0,reuseLists=0,changed=0;bool seenTracks=false,seenLists=false;
    var settings=new XmlReaderSettings{DtdProcessing=DtdProcessing.Ignore,XmlResolver=null,IgnoreWhitespace=true};
    using(var progress=new ProgressStream(memory,op))using(var reader=XmlReader.Create(progress,settings)){
     reader.MoveToContent();reader.ReadStartElement("plist");reader.MoveToContent();reader.ReadStartElement("dict");
     while(reader.MoveToContent()==XmlNodeType.Element){op.Check();string key=reader.ReadElementContentAsString("key","");reader.MoveToContent();
      if(key=="Tracks"){
       seenTracks=true;
       if(reader.IsEmptyElement){reader.Read();continue;}reader.ReadStartElement("dict");
       while(reader.MoveToContent()==XmlNodeType.Element){op.Check();string id=reader.ReadElementContentAsString("key","");reader.MoveToContent();string raw=reader.ReadOuterXml();string hash=Hash(raw);
        result.TrackHashes[id]=hash;
        if(previous!=null&&previous.TrackHashes.ContainsKey(id)&&previous.TrackHashes[id]==hash){result.Tracks[id]=previous.Tracks[id];reuseTracks++;}else{result.Tracks[id]=Decode(raw,op);changed++;}
        op.Report(Text.Get("XML差分・曲照合"),result.Tracks.Count,0,Text.Get("再利用 ")+reuseTracks+Text.Get(" / 新規・変更 ")+changed);
       }reader.ReadEndElement();
      }else if(key=="Playlists"){
       seenLists=true;
       if(reader.IsEmptyElement){reader.Read();continue;}reader.ReadStartElement("array");
       while(reader.MoveToContent()==XmlNodeType.Element){op.Check();string raw=reader.ReadOuterXml();string hash=Hash(raw);result.PlaylistHashes.Add(hash);
        if(oldLists.ContainsKey(hash)){result.Playlists.Add(oldLists[hash]);reuseLists++;}else result.Playlists.Add(Decode(raw,op));
        op.Report(Text.Get("XML差分・リスト照合"),result.Playlists.Count,0,Text.Get("再利用 ")+reuseLists);
       }reader.ReadEndElement();
      }else reader.Skip();
     }
     reader.ReadEndElement();reader.MoveToContent();reader.ReadEndElement();while(reader.Read()){op.Check();}
    }
    if(!seenTracks||!seenLists)throw new InvalidDataException(Text.Get("曲またはプレイリスト情報がありません。"));
    int removed=0;if(previous!=null)foreach(string id in previous.Tracks.Keys)if(!result.Tracks.ContainsKey(id))removed++;
    result.Summary=Text.Get("曲: 再利用 ")+reuseTracks+Text.Get(" / 新規・変更 ")+changed+Text.Get(" / 除外 ")+removed+Text.Get("、リスト再利用 ")+reuseLists;
    return result;
   }
  }
 }
}
