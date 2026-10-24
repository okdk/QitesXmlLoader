function Get-OutputFormats {
 @(
 [pscustomobject]@{Id='Copy';Label=(T '元のファイルを出力先にコピー');Extension='';Muxer='';Options=''},
 [pscustomobject]@{Id='Hardlink';Label=(T 'ハードリンクを設定');Extension='';Muxer='';Options=''},
 [pscustomobject]@{Id='Mp3';Label='MP3';Extension='mp3';Muxer='mp3';Options='-codec:a libmp3lame -q:a 2'},
 [pscustomobject]@{Id='Aac';Label='AAC / M4A';Extension='m4a';Muxer='ipod';Options='-codec:a aac -b:a 192k'},
 [pscustomobject]@{Id='Flac';Label='FLAC';Extension='flac';Muxer='flac';Options='-codec:a flac -compression_level 5'},
 [pscustomobject]@{Id='Alac';Label='ALAC / M4A';Extension='m4a';Muxer='ipod';Options='-codec:a alac'},
 [pscustomobject]@{Id='Wav';Label='WAV / PCM';Extension='wav';Muxer='wav';Options='-codec:a pcm_s16le'},
 [pscustomobject]@{Id='Opus';Label='Opus';Extension='opus';Muxer='opus';Options='-codec:a libopus -b:a 128k'},
 [pscustomobject]@{Id='Vorbis';Label='Ogg Vorbis';Extension='ogg';Muxer='ogg';Options='-codec:a libvorbis -q:a 5'},
 [pscustomobject]@{Id='Custom';Label=(T 'カスタム（詳細設定）');Extension='mka';Muxer='matroska';Options='-codec:a flac'}
 )
}
