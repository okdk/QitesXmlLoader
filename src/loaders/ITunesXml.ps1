param([string]$Path,[QitesXmlLoader.Operation]$Operation)
$Operation.Check()
[pscustomobject]@{Kind='ITunesXml';Path=$Path}
