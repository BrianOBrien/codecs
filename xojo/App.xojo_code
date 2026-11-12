#tag Class
Protected Class App
Inherits ConsoleApplication
	#tag Event
		Function Run(args() as String) As Integer
		  // xgt: the Xojo port's command-line tool, doing the jobs of the C gtinfo and gtcopy,
		  // so the same tests can check both against GDAL.
		  //   xgt -geotransform file.tif     the 6 numbers, GDAL order
		  //   xgt -corners file.tif          four corners and the centre
		  //   xgt [-raw out.raw] file.tif    summary; -raw also writes the decoded pixels
		  //   xgt copy [-c none|lzw|packbits] [-p] [-rows N] in.tif out.tif
		  If args.Count >= 2 Then
		    If args(1) = "copy" Then Return DoCopy(args)
		  End If
		  Return DoInfo(args)
		End Function
	#tag EndEvent

	#tag Method, Flags = &h0
		Function DoInfo(args() As String) As Integer
		  Var path, rawOut As String
		  Var gtOnly, cornersOnly As Boolean
		  Var i As Integer = 1
		  While i <= args.LastIndex
		    If args(i) = "-geotransform" Then
		      gtOnly = True
		    ElseIf args(i) = "-corners" Then
		      cornersOnly = True
		    ElseIf args(i) = "-raw" And i < args.LastIndex Then
		      i = i + 1
		      rawOut = args(i)
		    Else
		      path = args(i)
		    End If
		    i = i + 1
		  Wend
		  If path = "" Then
		    StdErr.WriteLine("usage: xgt [-geotransform | -corners] [-raw out.raw] file.tif | xgt copy ...")
		    Return 2
		  End If
		  Var err As String
		  Var f As GTFile = GTFile.Open(FullPath(path), err)
		  If f = Nil Then
		    StdErr.WriteLine("xgt: " + path + ": " + err)
		    Return 1
		  End If
		  If gtOnly Then
		    If Not f.HasTransform Then Return 1
		    Print(Num(f.GT(0)) + " " + Num(f.GT(1)) + " " + Num(f.GT(2)) + " " + Num(f.GT(3)) + " " + Num(f.GT(4)) + " " + Num(f.GT(5)))
		    Return 0
		  End If
		  If cornersOnly Then
		    Corner(f, "UpperLeft", 0, 0)
		    Corner(f, "LowerLeft", 0, f.Height)
		    Corner(f, "UpperRight", f.Width, 0)
		    Corner(f, "LowerRight", f.Width, f.Height)
		    Corner(f, "Center", f.Width / 2, f.Height / 2)
		    Return 0
		  End If
		  
		  Var order As String = "II (little-endian)"
		  If f.BigEndian Then order = "MM (big-endian)"
		  Var layout As String = "stripped"
		  If f.Tiled Then layout = "tiled"
		  Print("File: " + path)
		  Print("Byte order: " + order + ", " + f.NImages.ToString + " image(s) in the file")
		  Print("Size: " + f.Width.ToString + " x " + f.Height.ToString + ", " + f.SamplesPerPixel.ToString + " sample(s) of " _
		  + f.BitsPerSample.ToString + " bits, " + layout + ", compression " + f.Compression.ToString + ", predictor " + f.Predictor.ToString)
		  Print(f.Tags.Count.ToString + " tags, " + f.Keys.Count.ToString + " GeoKeys")
		  For Each k As GTGeoKey In f.Keys
		    Var v As String
		    Var d As Double
		    If k.Location = 0 Then
		      v = k.ValueOrIndex.ToString
		    ElseIf k.Location = TIFF.TIF_GEOASCIIPARAMS Then
		      v = """" + f.KeyString(k.ID) + """"
		    ElseIf f.KeyDouble(k.ID, d) Then
		      v = Num(d)
		    End If
		    Print("  GeoKey " + k.ID.ToString + " = " + v)
		  Next
		  If f.HasTransform Then
		    Print("Origin = (" + Num(f.GT(0)) + ", " + Num(f.GT(3)) + ")")
		    Print("Pixel Size = (" + Num(f.GT(1)) + ", " + Num(f.GT(5)) + ")")
		  End If
		  If rawOut <> "" Then
		    Var px As MemoryBlock = f.ReadImage(err)
		    If px = Nil Then
		      StdErr.WriteLine("xgt: cannot decode pixels: " + err)
		      Return 1
		    End If
		    Try
		      Var bs As BinaryStream = BinaryStream.Create(New FolderItem(FullPath(rawOut), FolderItem.PathModes.Native), True)
		      bs.Write(px.StringValue(0, px.Size))
		      bs.Close
		    Catch e As RuntimeException
		      StdErr.WriteLine("xgt: cannot write " + rawOut)
		      Return 1
		    End Try
		    Print("Pixels: " + px.Size.ToString + " bytes decoded to " + rawOut)
		  End If
		  Return 0
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function DoCopy(args() As String) As Integer
		  // Read with GTFile, write again with GTWriter, keeping pixels, georeferencing, EPSG and PixelIsPoint
		  Var o As New GTWriteOptions
		  o.Compression = TIFF.TIF_COMP_LZW
		  Var inPath, outPath As String
		  Var i As Integer = 2
		  While i <= args.LastIndex
		    If args(i) = "-c" And i < args.LastIndex Then
		      i = i + 1
		      Select Case args(i)
		      Case "none"
		        o.Compression = TIFF.TIF_COMP_NONE
		      Case "lzw"
		        o.Compression = TIFF.TIF_COMP_LZW
		      Case "packbits"
		        o.Compression = TIFF.TIF_COMP_PACKBITS
		      Else
		        StdErr.WriteLine("xgt copy: unknown compression " + args(i))
		        Return 2
		      End Select
		    ElseIf args(i) = "-p" Then
		      o.Predictor = TIFF.TIF_PRED_HORIZONTAL
		    ElseIf args(i) = "-rows" And i < args.LastIndex Then
		      i = i + 1
		      o.RowsPerStrip = args(i).ToInteger
		    ElseIf inPath = "" Then
		      inPath = args(i)
		    Else
		      outPath = args(i)
		    End If
		    i = i + 1
		  Wend
		  If inPath = "" Or outPath = "" Then
		    StdErr.WriteLine("usage: xgt copy [-c none|lzw|packbits] [-p] [-rows N] in.tif out.tif")
		    Return 2
		  End If
		  Var err As String
		  Var f As GTFile = GTFile.Open(FullPath(inPath), err)
		  If f = Nil Then
		    StdErr.WriteLine("xgt copy: " + inPath + ": " + err)
		    Return 1
		  End If
		  Var px As MemoryBlock = f.ReadImage(err)
		  If px = Nil Then
		    StdErr.WriteLine("xgt copy: " + inPath + ": " + err)
		    Return 1
		  End If
		  o.HasTransform = f.HasTransform
		  For k As Integer = 0 To 5
		    o.GT(k) = f.GT(k)
		  Next
		  o.Geographic = (f.KeyInt(TIFF.GK_GTModelType, 0) = 2)
		  If o.Geographic Then
		    o.EPSG = f.KeyInt(TIFF.GK_GeographicType, 0)
		  Else
		    o.EPSG = f.KeyInt(TIFF.GK_ProjectedCSType, 0)
		  End If
		  o.PixelIsPoint = (f.KeyInt(TIFF.GK_GTRasterType, 1) = 2)
		  o.SampleFormat = f.SampleFormat
		  o.Citation = f.KeyString(TIFF.GK_GTCitation)
		  o.Software = "geotiff xgt (Xojo)"
		  If Not GTWriter.Write(FullPath(outPath), px, f.Width, f.Height, f.SamplesPerPixel, f.BitsPerSample, o, err) Then
		    StdErr.WriteLine("xgt copy: " + outPath + ": " + err)
		    Return 1
		  End If
		  Return 0
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Corner(f As GTFile, name As String, col As Double, row As Double)
		  Var x, y As Double
		  If f.PixelToModel(col, row, x, y) Then Print(name + " (" + Num(x) + ", " + Num(y) + ")")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FullPath(p As String) As String
		  // A FolderItem resolves a relative path against the program's folder; use the current directory
		  If p.Left(1) = "/" Then Return p
		  Return SpecialFolder.CurrentWorkingDirectory.NativePath + "/" + p
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Num(v As Double) As String
		  // Enough digits to give back the same Double
		  Return Format(v, "-0.0000000000000000e+000")
		End Function
	#tag EndMethod


	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			Type="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			Type="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
