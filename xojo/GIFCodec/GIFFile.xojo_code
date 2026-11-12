#tag Class
Protected Class GIFFile
	#tag Note, Name = About
		A GIF, read or to be written. Ported from gif.c, which comes from Brian O'Brien's Readgif (1999)
		and Writegif (1998-99, the GIF export of WinFLI 4.0), with the writer's bugs fixed.
		  Var err As String
		  Var g As GIFFile = GIFFile.Read("/path/anim.gif", err)
		  Var rgba As MemoryBlock = g.Composite(3)      // frame 3 as a viewer shows it, Width*Height*4
		  If Not g.Write("/path/copy.gif", err) Then ...
		Disposal: 0 none, 1 keep, 2 restore background, 3 restore previous. Delay in 1/100 s.
		LoopCount: NETSCAPE2.0 loop count, 0 = forever, -1 = no extension.
	#tag EndNote

	#tag Method, Flags = &h0
		Shared Function Read(path As String, ByRef err As String) As GIFFile
		  #Pragma DisableBackgroundTasks
		  Var data As MemoryBlock
		  Try
		    Var bs As BinaryStream = BinaryStream.Open(New FolderItem(path, FolderItem.PathModes.Native), False)
		    data = bs.Read(bs.Length)
		    bs.Close
		  Catch e As RuntimeException
		    err = "cannot open the file"
		    Return Nil
		  End Try
		  If data = Nil Or data.Size < 13 Then
		    err = "not a GIF file"
		    Return Nil
		  End If
		  Var sig As String = data.StringValue(0, 6)
		  If sig <> "GIF87a" And sig <> "GIF89a" Then
		    err = "not a GIF file"
		    Return Nil
		  End If
		  data.LittleEndian = True
		  Var g As New GIFFile
		  g.Version89 = (sig = "GIF89a")
		  g.LoopCount = -1
		  g.mData = data
		  g.mPos = 6
		  g.Width = g.Get16
		  g.Height = g.Get16
		  Var packed As Integer = g.Get8
		  g.Background = g.Get8
		  Call g.Get8 // pixel aspect ratio
		  If (packed And &h80) <> 0 Then // global colour table
		    g.NColors = Bitwise.ShiftLeft(1, (packed And 7) + 1)
		    g.Palette = g.GetBytes(3 * g.NColors)
		  End If
		  
		  Var gceDelay, gceDisposal As Integer
		  Var gceTransparent As Integer = -1
		  While Not g.mBad
		    Var typ As Integer = g.Get8
		    If g.mBad Or typ = &h3B Then Exit While // trailer
		    If typ = &h21 Then // extension
		      Var extLabel As Integer = g.Get8
		      If extLabel = &hF9 Then // graphic control
		        Var bsz As Integer = g.Get8
		        Var pk As Integer = g.Get8
		        gceDelay = g.Get16
		        gceTransparent = g.Get8
		        If (pk And 1) = 0 Then gceTransparent = -1
		        gceDisposal = Bitwise.ShiftRight(pk, 2) And 7
		        g.mPos = g.mPos + Max(0, bsz - 4)
		        g.SkipSubBlocks
		      ElseIf extLabel = &hFF Then // application: NETSCAPE2.0 loop count
		        Var bsz As Integer = g.Get8
		        Var netscape As Boolean = (bsz = 11 And g.mPos + 11 <= data.Size)
		        If netscape Then netscape = (data.StringValue(g.mPos, 11) = "NETSCAPE2.0")
		        g.mPos = g.mPos + bsz
		        Var d As MemoryBlock = g.ReadSubBlocks
		        If netscape And d <> Nil And d.Size >= 3 Then
		          If d.Byte(0) = 1 Then g.LoopCount = d.Byte(1) + 256 * d.Byte(2)
		        End If
		      ElseIf extLabel = &hFE And g.Comment = "" Then // comment
		        Var d As MemoryBlock = g.ReadSubBlocks
		        If d <> Nil And d.Size > 0 Then g.Comment = d.StringValue(0, Min(d.Size, 255)).DefineEncoding(Encodings.ISOLatin1)
		      Else // plain text, more comments, unknown: skip
		        g.SkipSubBlocks
		      End If
		    ElseIf typ = &h2C Then // image descriptor
		      Var f As New GIFFrame
		      f.Left = g.Get16
		      f.Top = g.Get16
		      f.Width = g.Get16
		      f.Height = g.Get16
		      packed = g.Get8
		      f.Interlaced = (packed And &h40) <> 0
		      If (packed And &h80) <> 0 Then // local colour table
		        f.NColors = Bitwise.ShiftLeft(1, (packed And 7) + 1)
		        f.Palette = g.GetBytes(3 * f.NColors)
		        If f.Palette = Nil Then Exit While
		      End If
		      f.Delay = gceDelay
		      f.Disposal = gceDisposal
		      f.Transparent = gceTransparent
		      gceDelay = 0 // a graphic control block applies to one image
		      gceDisposal = 0
		      gceTransparent = -1
		  
		      Var minCode As Integer = g.Get8
		      Var codes As MemoryBlock = g.ReadSubBlocks
		      If g.mBad Or codes = Nil Or f.Width <= 0 Or f.Height <= 0 Then
		        g.mBad = True
		        Exit While
		      End If
		      Var npix As Integer = f.Width * f.Height
		      Var tmp As New MemoryBlock(npix)
		      f.Pixels = New MemoryBlock(npix)
		      If LZW.GIFDecode(codes, codes.Size, minCode, tmp, npix) < 0 Then
		        err = "corrupt LZW data"
		        Return Nil
		      End If
		      For row As Integer = 0 To f.Height - 1 // undo the interlace
		        Var y As Integer = row
		        If f.Interlaced Then y = InterlaceRow(row, f.Height)
		        f.Pixels.StringValue(y * f.Width, f.Width) = tmp.StringValue(row * f.Width, f.Width)
		      Next
		      g.Frames.Add(f)
		    Else
		      Exit While // unknown block: keep what we have
		    End If
		  Wend
		  g.mData = Nil
		  If g.Frames.Count = 0 Then
		    err = "no images in the file"
		    Return Nil
		  End If
		  Return g
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Shared Function InterlaceRow(n As Integer, height As Integer) As Integer
		  // Image row of the n-th stored row of an interlaced image (Brian's interlace class):
		  // every 8th row from 0, every 8th from 4, every 4th from 2, every 2nd from 1
		  Var pass1 As Integer = (height + 7) \ 8
		  Var pass2 As Integer = (height + 3) \ 8
		  Var pass3 As Integer = (height + 1) \ 4
		  If n < pass1 Then Return n * 8
		  n = n - pass1
		  If n < pass2 Then Return 4 + n * 8
		  n = n - pass2
		  If n < pass3 Then Return 2 + n * 4
		  n = n - pass3
		  Return 1 + n * 2
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Composite(upTo As Integer) As MemoryBlock
		  // Frames 0..upTo rendered the way a viewer shows them: Width*Height RGBA. The canvas starts
		  // transparent; each frame's disposal is applied before the next is drawn; transparent pixels
		  // leave what is underneath.
		  #Pragma DisableBackgroundTasks
		  Var n As Integer = Width * Height * 4
		  Var canvas As New MemoryBlock(n)
		  Var saved As New MemoryBlock(n)
		  If upTo > Frames.LastIndex Then upTo = Frames.LastIndex
		  For i As Integer = 0 To upTo
		    Var f As GIFFrame = Frames(i)
		    Var pal As MemoryBlock = f.Palette
		    Var ncol As Integer = f.NColors
		    If ncol = 0 Then
		      pal = Palette
		      ncol = NColors
		    End If
		    If i > 0 Then // the previous frame's disposal
		      Var p As GIFFrame = Frames(i - 1)
		      If p.Disposal = 2 Then // restore to background: transparent
		        For y As Integer = p.Top To Min(p.Top + p.Height, Height) - 1
		          For x As Integer = p.Left To Min(p.Left + p.Width, Width) - 1
		            canvas.UInt32Value((y * Width + x) * 4) = 0
		          Next
		        Next
		      ElseIf p.Disposal = 3 Then // restore to what was there before it
		        canvas.StringValue(0, n) = saved.StringValue(0, n)
		      End If
		    End If
		    If f.Disposal = 3 Then saved.StringValue(0, n) = canvas.StringValue(0, n)
		    For y As Integer = 0 To f.Height - 1
		      Var cy As Integer = f.Top + y
		      If cy >= Height Then Exit For
		      For x As Integer = 0 To f.Width - 1
		        Var cx As Integer = f.Left + x
		        If cx >= Width Then Exit For
		        Var idx As Integer = f.Pixels.Byte(y * f.Width + x)
		        If idx = f.Transparent Then Continue For
		        Var px As Integer = (cy * Width + cx) * 4
		        If idx < ncol Then
		          canvas.Byte(px) = pal.Byte(3 * idx)
		          canvas.Byte(px + 1) = pal.Byte(3 * idx + 1)
		          canvas.Byte(px + 2) = pal.Byte(3 * idx + 2)
		        Else
		          canvas.Byte(px) = 0 // index beyond the palette: black
		          canvas.Byte(px + 1) = 0
		          canvas.Byte(px + 2) = 0
		        End If
		        canvas.Byte(px + 3) = 255
		      Next
		    Next
		  Next
		  Return canvas
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Write(path As String, ByRef err As String) As Boolean
		  // GIF89a: palettes, loop count, comment, and per frame delay, disposal and transparency
		  #Pragma DisableBackgroundTasks
		  Var bs As BinaryStream
		  Try
		    bs = BinaryStream.Create(New FolderItem(path, FolderItem.PathModes.Native), True)
		  Catch e As RuntimeException
		    err = "cannot create the file"
		    Return False
		  End Try
		  bs.LittleEndian = True
		  bs.Write("GIF89a")
		  bs.WriteUInt16(Width)
		  bs.WriteUInt16(Height)
		  Var gbits As Integer = BitsFor(NColors)
		  If NColors > 0 Then
		    bs.WriteUInt8(&h80 Or &h70 Or (gbits - 1)) // global table, colour resolution 8, size (was always 0x80|0x70|bpp-1)
		  Else
		    bs.WriteUInt8(&h70)
		  End If
		  bs.WriteUInt8(Background)
		  bs.WriteUInt8(0) // pixel aspect ratio
		  If NColors > 0 Then WritePalette(bs, Palette, NColors, gbits)
		  If LoopCount >= 0 And Frames.Count > 1 Then // NETSCAPE2.0 loop count
		    bs.WriteUInt8(&h21)
		    bs.WriteUInt8(&hFF)
		    bs.WriteUInt8(11)
		    bs.Write("NETSCAPE2.0")
		    bs.WriteUInt8(3)
		    bs.WriteUInt8(1)
		    bs.WriteUInt16(LoopCount)
		    bs.WriteUInt8(0)
		  End If
		  If Comment <> "" Then
		    Var c As String = Comment.ConvertEncoding(Encodings.ISOLatin1)
		    bs.WriteUInt8(&h21)
		    bs.WriteUInt8(&hFE)
		    Var p As Integer = 0
		    While p < c.Bytes
		      Var k As Integer = Min(255, c.Bytes - p)
		      bs.WriteUInt8(k)
		      bs.Write(c.MiddleBytes(p, k))
		      p = p + k
		    Wend
		    bs.WriteUInt8(0)
		  End If
		  For Each f As GIFFrame In Frames
		    Var ncol As Integer = f.NColors
		    If ncol = 0 Then ncol = NColors
		    If ncol = 0 Then
		      bs.Close
		      err = "a frame has no palette"
		      Return False
		    End If
		    Var bits As Integer = BitsFor(ncol)
		    Var minCode As Integer = Max(2, bits) // GIF needs at least 2
		    bs.WriteUInt8(&h21) // graphic control extension
		    bs.WriteUInt8(&hF9)
		    bs.WriteUInt8(4)
		    Var pk As Integer = Bitwise.ShiftLeft(f.Disposal And 7, 2)
		    If f.Transparent >= 0 Then pk = pk Or 1
		    bs.WriteUInt8(pk)
		    bs.WriteUInt16(f.Delay)
		    bs.WriteUInt8(Max(0, f.Transparent))
		    bs.WriteUInt8(0)
		    bs.WriteUInt8(&h2C) // image descriptor, never interlaced on output
		    bs.WriteUInt16(f.Left)
		    bs.WriteUInt16(f.Top)
		    bs.WriteUInt16(f.Width)
		    bs.WriteUInt16(f.Height)
		    If f.NColors > 0 Then
		      bs.WriteUInt8(&h80 Or (bits - 1)) // was always 0x87
		      WritePalette(bs, f.Palette, f.NColors, bits)
		    Else
		      bs.WriteUInt8(0)
		    End If
		    bs.WriteUInt8(minCode)
		    Var codes As MemoryBlock = LZW.GIFEncode(f.Pixels, f.Width * f.Height, minCode)
		    Var p As Integer = 0
		    While p < codes.Size // sub-blocks of up to 255 bytes
		      Var k As Integer = Min(255, codes.Size - p)
		      bs.WriteUInt8(k)
		      bs.Write(codes.StringValue(p, k))
		      p = p + k
		    Wend
		    bs.WriteUInt8(0)
		  Next
		  bs.WriteUInt8(&h3B) // trailer
		  bs.Close
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function BitsFor(ncolors As Integer) As Integer
		  // Brian's get_bitPerPixel
		  Var b As Integer = 1
		  While Bitwise.ShiftLeft(1, b) < ncolors And b < 8
		    b = b + 1
		  Wend
		  Return b
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Sub WritePalette(bs As BinaryStream, pal As MemoryBlock, ncolors As Integer, bits As Integer)
		  // pad to a power of two with black
		  For i As Integer = 0 To Bitwise.ShiftLeft(1, bits) - 1
		    If i < ncolors And pal <> Nil Then
		      bs.Write(pal.StringValue(3 * i, 3))
		    Else
		      bs.WriteUInt8(0)
		      bs.WriteUInt8(0)
		      bs.WriteUInt8(0)
		    End If
		  Next
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Get8() As Integer
		  If mPos >= mData.Size Then
		    mBad = True
		    Return 0
		  End If
		  mPos = mPos + 1
		  Return mData.Byte(mPos - 1)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Get16() As Integer
		  Var a As Integer = Get8
		  Return a + 256 * Get8
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function GetBytes(n As Integer) As MemoryBlock
		  If mPos + n > mData.Size Then
		    mBad = True
		    Return Nil
		  End If
		  Var mb As New MemoryBlock(n)
		  mb.StringValue(0, n) = mData.StringValue(mPos, n)
		  mPos = mPos + n
		  Return mb
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ReadSubBlocks() As MemoryBlock
		  // A chain of sub-blocks (size, data, ..., 0) joined into one MemoryBlock
		  Var parts() As String
		  Var total As Integer
		  Do
		    Var size As Integer = Get8
		    If size = 0 Or mBad Then Exit Do
		    If mPos + size > mData.Size Then
		      mBad = True
		      Exit Do
		    End If
		    parts.Add(mData.StringValue(mPos, size))
		    total = total + size
		    mPos = mPos + size
		  Loop
		  Var mb As New MemoryBlock(total)
		  Var p As Integer = 0
		  For Each s As String In parts
		    mb.StringValue(p, s.Bytes) = s
		    p = p + s.Bytes
		  Next
		  Return mb
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub SkipSubBlocks()
		  Do
		    Var size As Integer = Get8
		    If size = 0 Or mBad Then Exit Do
		    mPos = mPos + size
		  Loop
		End Sub
	#tag EndMethod

	#tag Property, Flags = &h0
		Background As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Comment As String
	#tag EndProperty

	#tag Property, Flags = &h0
		Frames() As GIFFrame
	#tag EndProperty

	#tag Property, Flags = &h0
		Height As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		LoopCount As Integer = -1
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mBad As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mData As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPos As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		NColors As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Palette As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h0
		Version89 As Boolean
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
