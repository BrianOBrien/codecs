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
		  //   xgt gif file.gif | xgt gif -rgba out.raw file.gif | xgt gif copy in.gif out.gif
		  //   xgt fli file.fli | xgt fli -rgba out.raw file.fli | xgt fli copy in.fli out.flc | xgt fli pattern out.flc W H N | xgt fli togif in.fli out.gif
		  If args.Count >= 2 Then
		    If args(1) = "copy" Then Return DoCopy(args)
		    If args(1) = "gif" Then Return DoGIF(args)
		    If args(1) = "fli" Then Return DoFLI(args)
		  End If
		  Return DoInfo(args)
		End Function
	#tag EndEvent

	#tag Method, Flags = &h0
		Function DoFLI(args() As String) As Integer
		  // The jobs of the C flitool
		  Var err As String
		  If args.Count = 5 And args(2) = "copy" Then
		    Var f As FLIFile = FLIFile.Read(FullPath(args(3)), err)
		    If f = Nil Then
		      StdErr.WriteLine("xgt fli: " + args(3) + ": " + err)
		      Return 1
		    End If
		    If Not f.WriteFLC(FullPath(args(4)), err) Then
		      StdErr.WriteLine("xgt fli: " + args(4) + ": " + err)
		      Return 1
		    End If
		    Return 0
		  End If
		  If args.Count = 5 And args(2) = "togif" Then // WinFLI's "Save as GIF": FLIFile in, GIFFile out
		    Var f As FLIFile = FLIFile.Read(FullPath(args(3)), err)
		    If f = Nil Then
		      StdErr.WriteLine("xgt fli: " + args(3) + ": " + err)
		      Return 1
		    End If
		    Var g As New GIFFile
		    g.Width = f.Width
		    g.Height = f.Height
		    g.NColors = 256
		    g.Palette = f.Frames(0).Palette // global palette: the first frame's
		    g.LoopCount = 0
		    g.Comment = "Converted from FLI by the codecs Xojo modules (after WinFLI)"
		    For Each fr As FLIFrame In f.Frames
		      Var gf As New GIFFrame
		      gf.Width = f.Width
		      gf.Height = f.Height
		      gf.Pixels = fr.Pixels
		      gf.Delay = Max(2, (f.DelayMs + 5) \ 10) // hundredths of a second
		      gf.Disposal = 1
		      If StrComp(fr.Palette.StringValue(0, 768), g.Palette.StringValue(0, 768), 0) <> 0 Then
		        gf.NColors = 256 // the palette changed: a local colour table
		        gf.Palette = fr.Palette
		      End If
		      g.Frames.Add(gf)
		    Next
		    If Not g.Write(FullPath(args(4)), err) Then
		      StdErr.WriteLine("xgt fli: " + args(4) + ": " + err)
		      Return 1
		    End If
		    Return 0
		  End If
		  If args.Count = 7 And args(2) = "pattern" Then // the same test animation as flitool pattern
		    Var p As New FLIFile
		    Var w As Integer = args(4).ToInteger
		    Var h As Integer = args(5).ToInteger
		    Var n As Integer = args(6).ToInteger
		    p.Type = FLIFile.kFLCMagic
		    p.Width = w
		    p.Height = h
		    p.DelayMs = 50
		    Var seed As UInt32 = 12345
		    For i As Integer = 0 To n - 1
		      Var fr As New FLIFrame
		      fr.Palette = New MemoryBlock(768)
		      For k As Integer = 0 To 255
		        fr.Palette.Byte(3 * k) = (k + 40 * (i \ 5)) And 255
		        fr.Palette.Byte(3 * k + 1) = 255 - k
		        fr.Palette.Byte(3 * k + 2) = (k * 7 + i \ 5) And 255
		      Next
		      fr.Pixels = New MemoryBlock(w * h)
		      For y As Integer = 0 To h - 1
		        For x As Integer = 0 To w - 1
		          Var v As Integer = 200
		          If ((x \ 16 + y \ 16) And 1) = 1 Then v = 10
		          If x > 5 + 7 * i And x < 60 + 7 * i And y > 20 And y < 90 Then v = 100 + (x + y) Mod 3
		          If y = h \ 2 And (x * 31 + i) Mod 5 = 0 Then v = (x * 13 + i) And 255
		          If x = w - 1 And (y + i) Mod 4 = 0 Then v = i And 255
		          fr.Pixels.Byte(y * w + x) = v
		        Next
		      Next
		      For k As Integer = 0 To 39
		        seed = seed * 1103515245 + 12345
		        fr.Pixels.Byte((Bitwise.ShiftRight(seed, 8)) Mod (w * h)) = Bitwise.ShiftRight(seed, 24) And 255
		      Next
		      p.Frames.Add(fr)
		    Next
		    If Not p.WriteFLC(FullPath(args(3)), err) Then
		      StdErr.WriteLine("xgt fli: " + args(3) + ": " + err)
		      Return 1
		    End If
		    Return 0
		  End If
		  If args.Count = 5 And args(2) = "-rgba" Then
		    Var f As FLIFile = FLIFile.Read(FullPath(args(4)), err)
		    If f = Nil Then
		      StdErr.WriteLine("xgt fli: " + args(4) + ": " + err)
		      Return 1
		    End If
		    Try
		      Var bs As BinaryStream = BinaryStream.Create(New FolderItem(FullPath(args(3)), FolderItem.PathModes.Native), True)
		      Var npix As Integer = f.Width * f.Height
		      Var rgba As New MemoryBlock(npix * 4)
		      For Each fr As FLIFrame In f.Frames
		        For k As Integer = 0 To npix - 1
		          Var idx As Integer = fr.Pixels.Byte(k)
		          rgba.Byte(4 * k) = fr.Palette.Byte(3 * idx)
		          rgba.Byte(4 * k + 1) = fr.Palette.Byte(3 * idx + 1)
		          rgba.Byte(4 * k + 2) = fr.Palette.Byte(3 * idx + 2)
		          rgba.Byte(4 * k + 3) = 255
		        Next
		        bs.Write(rgba.StringValue(0, rgba.Size))
		      Next
		      bs.Close
		    Catch e As RuntimeException
		      StdErr.WriteLine("xgt fli: cannot write " + args(3))
		      Return 1
		    End Try
		    Return 0
		  End If
		  If args.Count = 3 Then
		    Var f As FLIFile = FLIFile.Read(FullPath(args(2)), err)
		    If f = Nil Then
		      StdErr.WriteLine("xgt fli: " + args(2) + ": " + err)
		      Return 1
		    End If
		    Var kind As String = "FLC"
		    If f.Type = FLIFile.kFLIMagic Then kind = "FLI"
		    Print("File: " + args(2) + " (" + kind + ")")
		    Print("Size: " + f.Width.ToString + " x " + f.Height.ToString + ", " + f.Frames.Count.ToString + " frame(s), " + f.DelayMs.ToString + " ms per frame")
		    Return 0
		  End If
		  StdErr.WriteLine("usage: xgt fli file.fli | -rgba out.raw file.fli | copy in.fli out.flc | pattern out.flc W H N")
		  Return 2
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function DoGIF(args() As String) As Integer
		  // The jobs of the C giftool
		  Var err As String
		  If args.Count = 5 And args(2) = "copy" Then
		    Var g As GIFFile = GIFFile.Read(FullPath(args(3)), err)
		    If g = Nil Then
		      StdErr.WriteLine("xgt gif: " + args(3) + ": " + err)
		      Return 1
		    End If
		    If Not g.Write(FullPath(args(4)), err) Then
		      StdErr.WriteLine("xgt gif: " + args(4) + ": " + err)
		      Return 1
		    End If
		    Return 0
		  End If
		  If args.Count = 6 And args(2) = "quantize" Then // at most K colours, then optimize (as giftool)
		    Var g As GIFFile = GIFFile.Read(FullPath(args(3)), err)
		    If g = Nil Then
		      StdErr.WriteLine("xgt gif: " + args(3) + ": " + err)
		      Return 1
		    End If
		    Var m As Integer = GIFOptimizer.Quantize(g, Val(args(5)), err)
		    Var o As GIFFile
		    If m >= 0 Then o = GIFOptimizer.Optimize(g, err)
		    If o = Nil Or Not o.Write(FullPath(args(4)), err) Then
		      StdErr.WriteLine("xgt gif: quantize " + args(3) + ": " + err)
		      Return 1
		    End If
		    Return 0
		  End If
		  If args.Count = 5 And args(2) = "optimize-raw" Then // GIFOptimizer output as is (no size check)
		    Var g As GIFFile = GIFFile.Read(FullPath(args(3)), err)
		    If g = Nil Then
		      StdErr.WriteLine("xgt gif: " + args(3) + ": " + err)
		      Return 1
		    End If
		    Var o As GIFFile = GIFOptimizer.Optimize(g, err)
		    If o = Nil Then
		      StdErr.WriteLine("xgt gif: optimize " + args(3) + ": " + err)
		      Return 1
		    End If
		    If Not o.Write(FullPath(args(4)), err) Then
		      StdErr.WriteLine("xgt gif: " + args(4) + ": " + err)
		      Return 1
		    End If
		    Return 0
		  End If
		  If args.Count = 5 And args(2) = "-rgba" Then
		    Var g As GIFFile = GIFFile.Read(FullPath(args(4)), err)
		    If g = Nil Then
		      StdErr.WriteLine("xgt gif: " + args(4) + ": " + err)
		      Return 1
		    End If
		    Try
		      Var bs As BinaryStream = BinaryStream.Create(New FolderItem(FullPath(args(3)), FolderItem.PathModes.Native), True)
		      For i As Integer = 0 To g.Frames.LastIndex
		        Var c As MemoryBlock = g.Composite(i)
		        bs.Write(c.StringValue(0, c.Size))
		      Next
		      bs.Close
		    Catch e As RuntimeException
		      StdErr.WriteLine("xgt gif: cannot write " + args(3))
		      Return 1
		    End Try
		    Return 0
		  End If
		  If args.Count = 3 Then
		    Var g As GIFFile = GIFFile.Read(FullPath(args(2)), err)
		    If g = Nil Then
		      StdErr.WriteLine("xgt gif: " + args(2) + ": " + err)
		      Return 1
		    End If
		    Print("Screen: " + g.Width.ToString + " x " + g.Height.ToString + ", global palette " + g.NColors.ToString _
		    + " colours, loop " + g.LoopCount.ToString + ", " + g.Frames.Count.ToString + " frame(s)")
		    For i As Integer = 0 To g.Frames.LastIndex
		      Var f As GIFFrame = g.Frames(i)
		      Print("  frame " + i.ToString + ": " + f.Width.ToString + "x" + f.Height.ToString + " at (" + f.Left.ToString + "," _
		      + f.Top.ToString + "), delay " + f.Delay.ToString + ", disposal " + f.Disposal.ToString + ", transparent " + f.Transparent.ToString)
		    Next
		    Return 0
		  End If
		  StdErr.WriteLine("usage: xgt gif file.gif | xgt gif -rgba out.raw file.gif | xgt gif copy in.gif out.gif")
		  Return 2
		End Function
	#tag EndMethod

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
