#tag Class
Protected Class GTFile
	#tag Note, Name = About
		A GeoTIFF opened for reading (the first image), ported from geotiff.c.
		  Var err As String
		  Var f As GTFile = GTFile.Open("/path/map.tif", err)
		  Var pixels As MemoryBlock = f.ReadImage(err)   // width*height*spp samples, interleaved, this machine's byte order
		  Var x, y As Double
		  Call f.PixelToModel(0, 0, x, y)                 // the top-left corner on the map
		Reads strips or tiles; uncompressed, LZW, Deflate or PackBits; horizontal predictor;
		8, 16 and 32-bit samples; GeoTIFF tie point + scale or transformation, GeoKeys.
	#tag EndNote

	#tag Method, Flags = &h0
		Shared Function Open(path As String, ByRef err As String) As GTFile
		  Var f As New GTFile
		  Try
		    Var fi As New FolderItem(path, FolderItem.PathModes.Native)
		    f.mStream = BinaryStream.Open(fi, False)
		  Catch e As RuntimeException
		    err = "cannot open the file"
		    Return Nil
		  End Try
		  Var h As MemoryBlock = f.ReadAt(0, 8)
		  If h = Nil Then
		    err = "file too short for a TIFF header"
		    Return Nil
		  End If
		  If h.UInt16Value(0) = TIFF.TIF_INTEL Then
		    f.BigEndian = False
		  ElseIf h.UInt16Value(0) = TIFF.TIF_MOTOROLA Then
		    f.BigEndian = True
		  Else
		    err = "not a TIFF file (no II or MM)"
		    Return Nil
		  End If
		  h.LittleEndian = Not f.BigEndian
		  If h.UInt16Value(2) <> TIFF.TIF_VERSION Then
		    If h.UInt16Value(2) = 43 Then err = "BigTIFF is not supported yet" Else err = "not a TIFF file (version is not 42)"
		    Return Nil
		  End If
		  f.IFDOffset = h.UInt32Value(4)
		  If Not f.ReadIFD(err) Then Return Nil
		  
		  // count the IFDs (only the first is decoded)
		  f.NImages = 1
		  Var nxt As Integer = f.IFDOffset
		  Do
		    Var b As MemoryBlock = f.ReadAt(nxt, 2)
		    If b = Nil Then Exit Do
		    Var b2 As MemoryBlock = f.ReadAt(nxt + 2 + 12 * b.UInt16Value(0), 4)
		    If b2 = Nil Then Exit Do
		    nxt = b2.UInt32Value(0)
		    If nxt = 0 Or f.NImages > 1000 Then Exit Do
		    f.NImages = f.NImages + 1
		  Loop
		  
		  // image description
		  f.Width = f.TagUInt(TIFF.TIF_IMAGEWIDTH, 0)
		  f.Height = f.TagUInt(TIFF.TIF_IMAGELENGTH, 0)
		  f.BitsPerSample = f.TagUInt(TIFF.TIF_BITSPERSAMPLE, 1)
		  f.SamplesPerPixel = f.TagUInt(TIFF.TIF_SAMPLESPERPIXEL, 1)
		  f.SampleFormat = f.TagUInt(TIFF.TIF_SAMPLEFORMAT, 1)
		  f.Compression = f.TagUInt(TIFF.TIF_COMPRESSION, TIFF.TIF_COMP_NONE)
		  f.Photometric = f.TagUInt(TIFF.TIF_PHOTOMETRICINTERPRETAION, 1)
		  f.Planar = f.TagUInt(TIFF.TIF_PLANARCONFIGURATION, 1)
		  f.Predictor = f.TagUInt(TIFF.TIF_PREDICTOR, TIFF.TIF_PRED_NONE)
		  f.Tiled = f.FindTag(TIFF.TIF_TILEOFFSETS) <> Nil
		  f.RowsPerStrip = f.TagUInt(TIFF.TIF_ROWSPERSTRIP, f.Height)
		  If f.RowsPerStrip = 0 Or f.RowsPerStrip > f.Height Then f.RowsPerStrip = f.Height
		  f.TileWidth = f.TagUInt(TIFF.TIF_TILEWIDTH, 0)
		  f.TileLength = f.TagUInt(TIFF.TIF_TILELENGTH, 0)
		  
		  // georeferencing: the transformation matrix, or tie point + pixel scale
		  Var t As GTTag = f.FindTag(TIFF.TIF_MODELTRANSFORMATION)
		  Var tp As GTTag = f.FindTag(TIFF.TIF_MODELTIEPOINT)
		  Var sc As GTTag = f.FindTag(TIFF.TIF_MODELPIXELSCALE)
		  If t <> Nil And t.Count >= 16 Then
		    f.HasTransform = True
		    f.GT(0) = t.Number(3)
		    f.GT(1) = t.Number(0)
		    f.GT(2) = t.Number(1)
		    f.GT(3) = t.Number(7)
		    f.GT(4) = t.Number(4)
		    f.GT(5) = t.Number(5)
		  ElseIf tp <> Nil And tp.Count >= 6 And sc <> Nil And sc.Count >= 2 Then
		    f.HasTransform = True
		    f.GT(1) = sc.Number(0)
		    f.GT(2) = 0
		    f.GT(0) = tp.Number(3) - tp.Number(0) * sc.Number(0)
		    f.GT(4) = 0
		    f.GT(5) = -sc.Number(1)
		    f.GT(3) = tp.Number(4) + tp.Number(1) * sc.Number(1)
		  End If
		  
		  // GeoKeys: header (version, revision, minor, count), then 4 shorts per key
		  Var kd As GTTag = f.FindTag(TIFF.TIF_GEOKEYDIRECTORY)
		  If kd <> Nil And kd.Count >= 4 Then
		    Var n As Integer = kd.Number(3)
		    If 4 + 4 * n > kd.Count Then n = (kd.Count - 4) \ 4
		    For i As Integer = 0 To n - 1
		      Var k As New GTGeoKey
		      k.ID = kd.Number(4 + 4 * i)
		      k.Location = kd.Number(5 + 4 * i)
		      k.Count = kd.Number(6 + 4 * i)
		      k.ValueOrIndex = kd.Number(7 + 4 * i)
		      f.Keys.Add(k)
		    Next
		  End If
		  
		  // PixelIsPoint: the tie point names a pixel centre; shift half a pixel like GDAL
		  If f.HasTransform And f.KeyInt(TIFF.GK_GTRasterType, 1) = 2 Then
		    f.GT(0) = f.GT(0) - 0.5 * f.GT(1) - 0.5 * f.GT(2)
		    f.GT(3) = f.GT(3) - 0.5 * f.GT(4) - 0.5 * f.GT(5)
		  End If
		  Return f
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ReadAt(offset As Integer, n As Integer) As MemoryBlock
		  // n bytes at offset, set to the file's byte order; Nil if the file is too short
		  If offset < 0 Or n < 0 Or offset + n > mStream.Length Then Return Nil
		  mStream.Position = offset
		  Var mb As MemoryBlock = mStream.Read(n)
		  If mb = Nil Or mb.Size < n Then Return Nil
		  mb.LittleEndian = Not BigEndian
		  Return mb
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ReadIFD(ByRef err As String) As Boolean
		  // Tag entries; values of 4 bytes or less live in the entry itself
		  Var b As MemoryBlock = ReadAt(IFDOffset, 2)
		  If b = Nil Then
		    err = "cannot read the IFD entry count"
		    Return False
		  End If
		  Var n As Integer = b.UInt16Value(0)
		  For i As Integer = 0 To n - 1
		    Var e As MemoryBlock = ReadAt(IFDOffset + 2 + 12 * i, 12)
		    If e = Nil Then
		      err = "cannot read a tag"
		      Return False
		    End If
		    Var t As New GTTag
		    t.ID = e.UInt16Value(0)
		    t.TypeCode = e.UInt16Value(2)
		    t.Count = e.UInt32Value(4)
		    Var size As Integer = TypeSize(t.TypeCode) * t.Count
		    If size <= 4 Then
		      t.Data = New MemoryBlock(4)
		      t.Data.StringValue(0, 4) = e.StringValue(8, 4)
		      t.Data.LittleEndian = Not BigEndian
		    Else
		      t.Data = ReadAt(e.UInt32Value(8), size)
		      If t.Data = Nil Then
		        err = "cannot read tag data"
		        Return False
		      End If
		    End If
		    Tags.Add(t)
		  Next
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Shared Function TypeSize(typeCode As Integer) As Integer
		  Select Case typeCode
		  Case TIFF.TIF_BYTE, TIFF.TIF_ASCII, TIFF.TIF_SBYTE, TIFF.TIF_UNDEFINE
		    Return 1
		  Case TIFF.TIF_SHORT, TIFF.TIF_SSHORT
		    Return 2
		  Case TIFF.TIF_LONG, TIFF.TIF_SLONG, TIFF.TIF_FLOAT
		    Return 4
		  Case TIFF.TIF_RATIONAL, TIFF.TIF_SRATIONAL, TIFF.TIF_DOUBLE
		    Return 8
		  End Select
		  Return 0
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function FindTag(id As Integer) As GTTag
		  For Each t As GTTag In Tags
		    If t.ID = id Then Return t
		  Next
		  Return Nil
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function TagUInt(id As Integer, dflt As Integer) As Integer
		  Var t As GTTag = FindTag(id)
		  If t = Nil Or t.Count < 1 Then Return dflt
		  Return t.Number(0)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function FindKey(id As Integer) As GTGeoKey
		  For Each k As GTGeoKey In Keys
		    If k.ID = id Then Return k
		  Next
		  Return Nil
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function KeyInt(id As Integer, dflt As Integer) As Integer
		  Var k As GTGeoKey = FindKey(id)
		  If k = Nil Or k.Location <> 0 Then Return dflt
		  Return k.ValueOrIndex
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function KeyString(id As Integer) As String
		  // An ASCII GeoKey (strings in GeoAsciiParams end with '|'); "" if missing
		  Var k As GTGeoKey = FindKey(id)
		  Var t As GTTag = FindTag(TIFF.TIF_GEOASCIIPARAMS)
		  If k = Nil Or t = Nil Or k.Location <> TIFF.TIF_GEOASCIIPARAMS Then Return ""
		  If k.ValueOrIndex + k.Count > t.Count Then Return ""
		  Var s As String = t.Data.StringValue(k.ValueOrIndex, k.Count)
		  If s.Right(1) = "|" Then s = s.Left(s.Length - 1)
		  Return s.DefineEncoding(Encodings.ASCII)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function KeyDouble(id As Integer, ByRef value As Double) As Boolean
		  Var k As GTGeoKey = FindKey(id)
		  Var t As GTTag = FindTag(TIFF.TIF_GEODOUBLEPARAMS)
		  If k = Nil Or t = Nil Or k.Location <> TIFF.TIF_GEODOUBLEPARAMS Or k.ValueOrIndex >= t.Count Then Return False
		  value = t.Number(k.ValueOrIndex)
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function PixelToModel(col As Double, row As Double, ByRef x As Double, ByRef y As Double) As Boolean
		  // Raster (0,0 = top-left corner of the top-left pixel) to model coordinates
		  If Not HasTransform Then Return False
		  x = GT(0) + GT(1) * col + GT(2) * row
		  y = GT(3) + GT(4) * col + GT(5) * row
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ReadImage(ByRef err As String) As MemoryBlock
		  // Width*Height*SamplesPerPixel samples, interleaved, in this machine's byte order
		  #Pragma DisableBackgroundTasks
		  Var bytes As Integer = BitsPerSample \ 8
		  Var spp As Integer = SamplesPerPixel
		  If BitsPerSample Mod 8 <> 0 Or (bytes <> 1 And bytes <> 2 And bytes <> 4) Then
		    err = "only 8, 16 and 32-bit samples are supported"
		    Return Nil
		  End If
		  If Planar <> 1 And spp > 1 Then
		    err = "separate planes (PlanarConfiguration 2) are not supported yet"
		    Return Nil
		  End If
		  If Compression <> TIFF.TIF_COMP_NONE And Compression <> TIFF.TIF_COMP_LZW And Compression <> TIFF.TIF_COMP_DEFLATE _
		    And Compression <> TIFF.TIF_COMP_DEFLATE_OLD And Compression <> TIFF.TIF_COMP_PACKBITS Then
		    err = "compression not supported (none, LZW, Deflate and PackBits are)"
		    Return Nil
		  End If
		  If Predictor = TIFF.TIF_PRED_FLOAT Then
		    err = "the floating-point predictor (3) is not supported yet"
		    Return Nil
		  End If
		  
		  Var offs, counts As GTTag
		  Var blockW, blockH As Integer
		  If Tiled Then
		    offs = FindTag(TIFF.TIF_TILEOFFSETS)
		    counts = FindTag(TIFF.TIF_TILEBYTECOUNTS)
		    blockW = TileWidth
		    blockH = TileLength
		  Else
		    offs = FindTag(TIFF.TIF_STRIPOFFSETS)
		    counts = FindTag(TIFF.TIF_STRIPBYTECOUNTS)
		    blockW = Width
		    blockH = RowsPerStrip
		  End If
		  If offs = Nil Or counts = Nil Or blockW = 0 Or blockH = 0 Or Width = 0 Or Height = 0 Then
		    err = "missing strip or tile layout"
		    Return Nil
		  End If
		  Var across As Integer = (Width + blockW - 1) \ blockW
		  Var down As Integer = (Height + blockH - 1) \ blockH
		  Var nBlocks As Integer = across * down
		  If offs.Count < nBlocks Or counts.Count < nBlocks Then
		    err = "fewer strips or tiles than the image needs"
		    Return Nil
		  End If
		  Var pixelBytes As Integer = bytes * spp
		  Var blockBytes As Integer = blockW * blockH * pixelBytes
		  If blockBytes > 1024 * 1024 * 1024 Or Width * Height * pixelBytes > 2 * 1024 * 1024 * 1024 Then
		    err = "image too large"
		    Return Nil
		  End If
		  Var image As New MemoryBlock(Width * Height * pixelBytes)
		  Var mask As Integer = Bitwise.ShiftLeft(1, 8 * bytes) - 1
		  
		  For b As Integer = 0 To nBlocks - 1
		    Var count As Integer = counts.Number(b)
		    Var packed As MemoryBlock = ReadAt(offs.Number(b), count)
		    If packed = Nil Then
		      err = "cannot read a strip or tile"
		      Return Nil
		    End If
		    Var block As New MemoryBlock(blockBytes)
		    Var n As Integer
		    Select Case Compression
		    Case TIFF.TIF_COMP_LZW
		      n = LZW.Decode(packed, count, block, blockBytes)
		    Case TIFF.TIF_COMP_PACKBITS
		      n = PackBits.Decode(packed, count, block, blockBytes)
		    Case TIFF.TIF_COMP_DEFLATE, TIFF.TIF_COMP_DEFLATE_OLD
		      Var inf As New Inflater
		      n = inf.Zlib(packed, count, block, blockBytes)
		    Else
		      n = Min(count, blockBytes)
		      If n > 0 Then block.StringValue(0, n) = packed.StringValue(0, n)
		    End Select
		    If n < 0 Then
		      err = "corrupt compressed data"
		      Return Nil
		    End If
		    block.LittleEndian = Not BigEndian // samples are in the file's byte order
		  
		    Var bx As Integer = (b Mod across) * blockW
		    Var by As Integer = (b \ across) * blockH
		    Var w As Integer = Min(blockW, Width - bx)
		    For r As Integer = 0 To blockH - 1
		      If by + r >= Height Then Exit For
		      Var src As Integer = r * blockW * pixelBytes
		      Var dst As Integer = ((by + r) * Width + bx) * pixelBytes
		      // read in file order, undo the predictor, write in host order
		      For i As Integer = 0 To w * spp - 1
		        Var v As Integer
		        Select Case bytes
		        Case 1
		          v = block.Byte(src + i)
		        Case 2
		          v = block.UInt16Value(src + 2 * i)
		        Else
		          v = block.UInt32Value(src + 4 * i)
		        End Select
		        If Predictor = TIFF.TIF_PRED_HORIZONTAL And i >= spp Then
		          Select Case bytes
		          Case 1
		            v = (v + image.Byte(dst + i - spp)) And mask
		          Case 2
		            v = (v + image.UInt16Value(dst + 2 * (i - spp))) And mask
		          Else
		            v = (v + image.UInt32Value(dst + 4 * (i - spp))) And mask
		          End Select
		        End If
		        Select Case bytes
		        Case 1
		          image.Byte(dst + i) = v
		        Case 2
		          image.UInt16Value(dst + 2 * i) = v
		        Else
		          image.UInt32Value(dst + 4 * i) = v
		        End Select
		      Next
		    Next
		  Next
		  Return image
		End Function
	#tag EndMethod

	#tag Property, Flags = &h0
		BigEndian As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		BitsPerSample As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Compression As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		GT(5) As Double
	#tag EndProperty

	#tag Property, Flags = &h0
		HasTransform As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		Height As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		IFDOffset As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Keys() As GTGeoKey
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mStream As BinaryStream
	#tag EndProperty

	#tag Property, Flags = &h0
		NImages As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Photometric As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Planar As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Predictor As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		RowsPerStrip As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		SampleFormat As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		SamplesPerPixel As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Tags() As GTTag
	#tag EndProperty

	#tag Property, Flags = &h0
		Tiled As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		TileLength As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		TileWidth As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Width As Integer
	#tag EndProperty


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
