#tag Module
Protected Module GTWriter
	#tag Note, Name = About
		Writes a GeoTIFF, ported from gtwrite.c: classic TIFF, little-endian, strips;
		uncompressed, LZW or PackBits; horizontal predictor; ModelPixelScale + ModelTiepoint
		(or ModelTransformation when rotated) and GeoKeys. File layout: header, strips, the
		values of big tags, then the IFD; the header points at the IFD.
		  Var o As New GTWriteOptions
		  o.HasTransform = True : o.GT = ... : o.EPSG = 4326 : o.Geographic = True
		  If Not GTWriter.Write("/path/out.tif", pixels, w, h, 3, 8, o, err) Then ...
	#tag EndNote

	#tag Method, Flags = &h0
		Function Write(path As String, pixels As MemoryBlock, width As Integer, height As Integer, spp As Integer, bitsPerSample As Integer, o As GTWriteOptions, ByRef err As String) As Boolean
		  // pixels: width*height*spp samples, interleaved, this machine's byte order (as GTFile.ReadImage gives)
		  #Pragma DisableBackgroundTasks
		  If o = Nil Then o = New GTWriteOptions
		  Var bytes As Integer = bitsPerSample \ 8
		  If width <= 0 Or height <= 0 Or spp < 1 Or spp > 4 Or bitsPerSample Mod 8 <> 0 Or (bytes <> 1 And bytes <> 2 And bytes <> 4) Then
		    err = "need 1-4 samples per pixel of 8, 16 or 32 bits"
		    Return False
		  End If
		  If pixels = Nil Or pixels.Size < width * height * spp * bytes Then
		    err = "not enough pixel data"
		    Return False
		  End If
		  If o.Compression <> TIFF.TIF_COMP_NONE And o.Compression <> TIFF.TIF_COMP_LZW And o.Compression <> TIFF.TIF_COMP_PACKBITS Then
		    err = "can write uncompressed, LZW or PackBits"
		    Return False
		  End If
		  
		  Var rowBytes As Integer = width * spp * bytes
		  Var rps As Integer = o.RowsPerStrip
		  If rps <= 0 Then rps = Max(1, 8192 \ rowBytes)
		  If rps > height Then rps = height
		  Var nStrips As Integer = (height + rps - 1) \ rps
		  Var offsets(), counts() As Integer
		  
		  Var bs As BinaryStream
		  Try
		    bs = BinaryStream.Create(New FolderItem(path, FolderItem.PathModes.Native), True)
		  Catch e As RuntimeException
		    err = "cannot create the file"
		    Return False
		  End Try
		  bs.LittleEndian = True
		  bs.WriteUInt16(TIFF.TIF_INTEL)
		  bs.WriteUInt16(TIFF.TIF_VERSION)
		  bs.WriteUInt32(0) // IFD offset, filled in at the end
		  
		  // strips: copy, predictor, little-endian, compress
		  Var mask As Integer = Bitwise.ShiftLeft(1, 8 * bytes) - 1
		  For s As Integer = 0 To nStrips - 1
		    Var rows As Integer = Min(rps, height - s * rps)
		    Var strip As New MemoryBlock(rows * rowBytes)
		    strip.LittleEndian = True
		    Var rowSamples As Integer = width * spp
		    For r As Integer = 0 To rows - 1
		      Var src As Integer = (s * rps + r) * rowBytes
		      Var dst As Integer = r * rowBytes
		      For i As Integer = 0 To rowSamples - 1
		        Var v, prev As Integer
		        Select Case bytes
		        Case 1
		          v = pixels.Byte(src + i)
		          If i >= spp Then prev = pixels.Byte(src + i - spp)
		        Case 2
		          v = pixels.UInt16Value(src + 2 * i)
		          If i >= spp Then prev = pixels.UInt16Value(src + 2 * (i - spp))
		        Else
		          v = pixels.UInt32Value(src + 4 * i)
		          If i >= spp Then prev = pixels.UInt32Value(src + 4 * (i - spp))
		        End Select
		        If o.Predictor = TIFF.TIF_PRED_HORIZONTAL And i >= spp Then v = (v - prev) And mask
		        Select Case bytes
		        Case 1
		          strip.Byte(dst + i) = v
		        Case 2
		          strip.UInt16Value(dst + 2 * i) = v
		        Else
		          strip.UInt32Value(dst + 4 * i) = v
		        End Select
		      Next
		    Next
		    Var packed As MemoryBlock = strip
		    If o.Compression = TIFF.TIF_COMP_LZW Then
		      packed = LZW.Encode(strip, strip.Size)
		    ElseIf o.Compression = TIFF.TIF_COMP_PACKBITS Then
		      packed = PackBits.Encode(strip, strip.Size)
		    End If
		    offsets.Add(bs.Position)
		    counts.Add(packed.Size)
		    bs.Write(packed.StringValue(0, packed.Size))
		  Next
		  
		  // tags
		  Var tags() As GTOutTag
		  Var bps() As Integer
		  Var sf() As Integer
		  For i As Integer = 1 To spp
		    bps.Add(bitsPerSample)
		    sf.Add(o.SampleFormat)
		  Next
		  Var photometric As Integer = 1 // grey, 0 = black
		  If spp >= 3 Then photometric = 2 // RGB
		  tags.Add(MakeLongs(TIFF.TIF_IMAGEWIDTH, Array(width)))
		  tags.Add(MakeLongs(TIFF.TIF_IMAGELENGTH, Array(height)))
		  tags.Add(MakeShorts(TIFF.TIF_BITSPERSAMPLE, bps))
		  tags.Add(MakeShorts(TIFF.TIF_COMPRESSION, Array(o.Compression)))
		  tags.Add(MakeShorts(TIFF.TIF_PHOTOMETRICINTERPRETAION, Array(photometric)))
		  tags.Add(MakeLongs(TIFF.TIF_STRIPOFFSETS, offsets))
		  tags.Add(MakeShorts(TIFF.TIF_SAMPLESPERPIXEL, Array(spp)))
		  tags.Add(MakeLongs(TIFF.TIF_ROWSPERSTRIP, Array(rps)))
		  tags.Add(MakeLongs(TIFF.TIF_STRIPBYTECOUNTS, counts))
		  tags.Add(MakeShorts(TIFF.TIF_PLANARCONFIGURATION, Array(1)))
		  If spp = 2 Or spp = 4 Then tags.Add(MakeShorts(TIFF.TIF_EXTRASAMPLES, Array(2))) // last sample is alpha
		  If o.Software <> "" Then tags.Add(MakeAscii(TIFF.TIF_SOFTWARE, o.Software))
		  If o.Predictor = TIFF.TIF_PRED_HORIZONTAL Then tags.Add(MakeShorts(TIFF.TIF_PREDICTOR, Array(TIFF.TIF_PRED_HORIZONTAL)))
		  If o.SampleFormat > 1 Then tags.Add(MakeShorts(TIFF.TIF_SAMPLEFORMAT, sf))
		  
		  // georeferencing
		  If o.HasTransform Then
		    Var g(5) As Double
		    For i As Integer = 0 To 5
		      g(i) = o.GT(i)
		    Next
		    If o.PixelIsPoint Then // tie the pixel centre, not its corner
		      g(0) = g(0) + 0.5 * g(1) + 0.5 * g(2)
		      g(3) = g(3) + 0.5 * g(4) + 0.5 * g(5)
		    End If
		    If g(2) = 0 And g(4) = 0 Then
		      tags.Add(MakeDoubles(TIFF.TIF_MODELPIXELSCALE, Array(g(1), -g(5), 0.0)))
		      tags.Add(MakeDoubles(TIFF.TIF_MODELTIEPOINT, Array(0.0, 0.0, 0.0, g(0), g(3), 0.0)))
		    Else // rotated or sheared: the full matrix
		      tags.Add(MakeDoubles(TIFF.TIF_MODELTRANSFORMATION, Array(g(1), g(2), 0.0, g(0), g(4), g(5), 0.0, g(3), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)))
		    End If
		  End If
		  If o.HasTransform Or o.EPSG <> 0 Then
		    Var keys() As Integer = Array(1, 1, 1, 0) // version 1, revision 1.1, count filled in below
		    Var model As Integer = 1
		    If o.Geographic Then model = 2
		    Var raster As Integer = 1
		    If o.PixelIsPoint Then raster = 2
		    keys.Add(TIFF.GK_GTModelType)
		    keys.Add(0)
		    keys.Add(1)
		    keys.Add(model)
		    keys.Add(TIFF.GK_GTRasterType)
		    keys.Add(0)
		    keys.Add(1)
		    keys.Add(raster)
		    Var cit As String
		    If o.Citation <> "" Then
		      cit = o.Citation + "|" // GeoAsciiParams strings end with '|'
		      keys.Add(TIFF.GK_GTCitation)
		      keys.Add(TIFF.TIF_GEOASCIIPARAMS)
		      keys.Add(cit.Bytes)
		      keys.Add(0)
		    End If
		    If o.EPSG <> 0 Then
		      If o.Geographic Then keys.Add(TIFF.GK_GeographicType) Else keys.Add(TIFF.GK_ProjectedCSType)
		      keys.Add(0)
		      keys.Add(1)
		      keys.Add(o.EPSG)
		    End If
		    keys(3) = (keys.Count - 4) \ 4
		    tags.Add(MakeShorts(TIFF.TIF_GEOKEYDIRECTORY, keys))
		    If cit <> "" Then tags.Add(MakeAscii(TIFF.TIF_GEOASCIIPARAMS, cit))
		  End If
		  
		  // sort by id (the IFD must be in order)
		  For i As Integer = 1 To tags.LastIndex
		    Var j As Integer = i
		    While j > 0 And tags(j - 1).ID > tags(j).ID
		      Var tmp As GTOutTag = tags(j)
		      tags(j) = tags(j - 1)
		      tags(j - 1) = tmp
		      j = j - 1
		    Wend
		  Next
		  
		  // values that do not fit in 4 bytes, each on an even offset
		  For Each t As GTOutTag In tags
		    If t.Data.Size > 4 Then
		      If bs.Position Mod 2 = 1 Then bs.WriteUInt8(0)
		      t.Offset = bs.Position
		      bs.Write(t.Data.StringValue(0, t.Data.Size))
		    End If
		  Next
		  
		  // the IFD
		  If bs.Position Mod 2 = 1 Then bs.WriteUInt8(0)
		  Var ifd As Integer = bs.Position
		  bs.WriteUInt16(tags.Count)
		  For Each t As GTOutTag In tags
		    bs.WriteUInt16(t.ID)
		    bs.WriteUInt16(t.TypeCode)
		    bs.WriteUInt32(t.Count)
		    If t.Data.Size > 4 Then
		      bs.WriteUInt32(t.Offset)
		    Else
		      Var v As New MemoryBlock(4) // the value itself, left-justified
		      v.StringValue(0, t.Data.Size) = t.Data.StringValue(0, t.Data.Size)
		      bs.Write(v.StringValue(0, 4))
		    End If
		  Next
		  bs.WriteUInt32(0) // no next IFD
		  bs.Position = 4
		  bs.WriteUInt32(ifd)
		  bs.Close
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function MakeShorts(id As Integer, v() As Integer) As GTOutTag
		  Var t As New GTOutTag
		  t.ID = id
		  t.TypeCode = TIFF.TIF_SHORT
		  t.Count = v.Count
		  t.Data = New MemoryBlock(2 * v.Count)
		  t.Data.LittleEndian = True
		  For i As Integer = 0 To v.LastIndex
		    t.Data.UInt16Value(2 * i) = v(i)
		  Next
		  Return t
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function MakeLongs(id As Integer, v() As Integer) As GTOutTag
		  Var t As New GTOutTag
		  t.ID = id
		  t.TypeCode = TIFF.TIF_LONG
		  t.Count = v.Count
		  t.Data = New MemoryBlock(4 * v.Count)
		  t.Data.LittleEndian = True
		  For i As Integer = 0 To v.LastIndex
		    t.Data.UInt32Value(4 * i) = v(i)
		  Next
		  Return t
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function MakeDoubles(id As Integer, v() As Double) As GTOutTag
		  Var t As New GTOutTag
		  t.ID = id
		  t.TypeCode = TIFF.TIF_DOUBLE
		  t.Count = v.Count
		  t.Data = New MemoryBlock(8 * v.Count)
		  t.Data.LittleEndian = True
		  For i As Integer = 0 To v.LastIndex
		    t.Data.DoubleValue(8 * i) = v(i)
		  Next
		  Return t
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function MakeAscii(id As Integer, s As String) As GTOutTag
		  Var t As New GTOutTag
		  t.ID = id
		  t.TypeCode = TIFF.TIF_ASCII
		  t.Count = s.Bytes + 1 // with the closing zero
		  t.Data = New MemoryBlock(t.Count)
		  t.Data.StringValue(0, s.Bytes) = s
		  Return t
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
End Module
#tag EndModule
