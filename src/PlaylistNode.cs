using System;
using System.Collections.Generic;
using System.ComponentModel;
namespace QitesXmlLoader {
 public sealed class PlaylistNode:INotifyPropertyChanged {
  public string Id{get;set;}public string Name{get;set;}public bool IsFolder{get;set;}public bool IsSmart{get;set;}
  public object Payload{get;set;}public object[] LeafTracks{get;set;}
  public PlaylistNode Parent{get;set;}
  public List<PlaylistNode> Children{get;private set;}
  bool? state=false;
  public PlaylistNode(){Children=new List<PlaylistNode>();LeafTracks=new object[0];}
  public string DisplayName{get{return Name+Text.Get(IsFolder?Text.Get(" [フォルダ]"):IsSmart?Text.Get(" [スマート／XML]"):Text.Get(" [通常]"));}}
  public bool Selected{get{return state==true;}set{SelectedState=value;}}
  public bool? SelectedState{get{return state;}set{SetRecursive(value==true);if(Parent!=null)Parent.UpdateState();}}
  void SetRecursive(bool value){state=value;foreach(var child in Children)child.SetRecursive(value);Changed("SelectedState");Changed("Selected");}
  void UpdateState(){bool all=Children.Count>0,any=false;foreach(var child in Children){all&=child.state==true;any|=child.state!=false;}state=all?(bool?)true:any?(bool?)null:false;Changed("SelectedState");Changed("Selected");if(Parent!=null)Parent.UpdateState();}
  public object[] Tracks{get{if(!IsFolder)return LeafTracks;var tracks=new List<object>();foreach(var child in Children)tracks.AddRange(child.Tracks);return tracks.ToArray();}}
  public void RefreshNames(){Changed("DisplayName");foreach(var child in Children)child.RefreshNames();}
  public event PropertyChangedEventHandler PropertyChanged;
  void Changed(string name){var handler=PropertyChanged;if(handler!=null)handler(this,new PropertyChangedEventArgs(name));}
 }
}
