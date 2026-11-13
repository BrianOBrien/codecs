#tag Class
Protected Class FLIFile
	#tag Note, Name = About
		An Autodesk Animator FLI or FLC, ported from fli.c. The reader follows Brian O'Brien's
		Readfli (1998-2000), the core of WinFLI 98, with its bugs fixed; the FLC writer is new.
		  Var err As String
		  Var f As FLIFile = FLIFile.Read("/path/anim.fli", err)
		  Var px As MemoryBlock = f.Frames(0).Pixels      // Width*Height colour indices
		  Var pal As MemoryBlock = f.Frames(0).Palette    // 256 x RGB
		  If Not f.WriteFLC("/path/copy.flc", err) Then ...
		Writer: BYTE_RUN first frame, SS2 deltas (LC for odd widths), COLOR_256 when the palette
		changes, and the ring frame back to the start.
	#tag EndNote

	#tag Constant, Name = kFLIMagic, Type = Double, Dynamic = False, Default = \"44817", Scope = Public
	#tag EndConstant

	#tag Constant, Name = kFLCMagic, Type = Double, Dynamic = False, Default = \"44818", Scope = Public
	#tag EndConstant

	#tag Method, Flags = &h0
		Shared Function Read(path As String, ByRef err As String) As FLIFile
		  #Pragma DisableBackgroundTasks
		  Var d As MemoryBlock
		  Try
		    Var bs As BinaryStream = BinaryStream.Open(New FolderItem(path, FolderItem.PathModes.Native), False)
		    d = bs.Read(bs.Length)
		    bs.Close
		  Catch e As RuntimeException
		    err = "cannot open the file"
		    Return Nil
		  End Try
		  If d = Nil Or d.Size < 128 Then
		    err = "not an FLI or FLC file"
		    Return Nil
		  End If
		  d.LittleEndian = True
		  Var f As New FLIFile
		  f.Type = d.UInt16Value(4)
		  If f.Type <> kFLIMagic And f.Type <> kFLCMagic Then
		    err = "not an FLI or FLC file"
		    Return Nil
		  End If
		  Var total As Integer = d.UInt16Value(6)
		  f.Width = d.UInt16Value(8)
		  f.Height = d.UInt16Value(10)
		  Var speed As Integer = d.UInt32Value(16)
		  If f.Type = kFLIMagic Then f.DelayMs = (speed * 1000 + 35) \ 70 Else f.DelayMs = speed // fix: FLC is in ms
		  If f.Width <= 0 Or f.Height <= 0 Or total <= 0 Then
		    err = "bad header"
		    Return Nil
		  End If
		  Var npix As Integer = f.Width * f.Height
		  Var px As New MemoryBlock(npix)
		  Var pal As New MemoryBlock(768)
		  Var pos As Integer = 128
		  If f.Type = kFLCMagic And d.UInt32Value(80) >= 128 And d.UInt32Value(80) < d.Size Then pos = d.UInt32Value(80) // oframe1
		  
		  While f.Frames.Count < total And pos + 16 <= d.Size
		    Var fsize As Integer = d.UInt32Value(pos)
		    Var ftype As Integer = d.UInt16Value(pos + 4)
		    Var nchunks As Integer = d.UInt16Value(pos + 6)
		    If fsize < 16 Or pos + fsize > d.Size Then fsize = d.Size - pos // a short last frame: use what is there
		    Var fend As Integer = pos + fsize
		    If ftype <> &hF1FA Then // prefix or unknown block: skip it
		      pos = pos + fsize
		      Continue While
		    End If
		    Var p As Integer = pos + 16
		    For i As Integer = 0 To nchunks - 1
		      If fend - p < 6 Then Exit For
		      Var csize As Integer = d.UInt32Value(p)
		      Var chunkType As Integer = d.UInt16Value(p + 4)
		      Var cend As Integer = p + csize
		      If csize < 6 Or csize > fend - p Then cend = fend
		      Select Case chunkType
		      Case 4 // COLOR_256
		        DoColor(d, p + 6, cend, pal, False)
		      Case 11 // COLOR_64
		        DoColor(d, p + 6, cend, pal, True)
		      Case 15 // BYTE_RUN
		        DoBrun(d, p + 6, cend, px, f.Width, f.Height)
		      Case 12 // LC
		        DoLC(d, p + 6, cend, px, f.Width, f.Height)
		      Case 7 // SS2
		        DoSS2(d, p + 6, cend, px, f.Width, f.Height)
		      Case 13 // BLACK
		        px = New MemoryBlock(npix)
		      Case 16 // COPY
		        Var n As Integer = Min(npix, cend - p - 6)
		        If n > 0 Then px.StringValue(0, n) = d.StringValue(p + 6, n)
		      End Select // postage stamp and anything else: skip
		      p = cend
		    Next
		    Var fr As New FLIFrame
		    fr.Pixels = New MemoryBlock(npix)
		    fr.Pixels.StringValue(0, npix) = px.StringValue(0, npix)
		    fr.Palette = New MemoryBlock(768)
		    fr.Palette.StringValue(0, 768) = pal.StringValue(0, 768)
		    f.Frames.Add(fr)
		    pos = pos + fsize
		  Wend
		  If f.Frames.Count = 0 Then
		    err = "no frames in the file"
		    Return Nil
		  End If
		  Return f
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Sub DoColor(d As MemoryBlock, p As Integer, e As Integer, pal As MemoryBlock, sixBit As Boolean)
		  If e - p < 2 Then Return
		  Var npackets As Integer = d.UInt16Value(p)
		  p = p + 2
		  Var color As Integer = 0
		  While npackets > 0 And e - p >= 2
		    npackets = npackets - 1
		    color = color + d.Byte(p)
		    Var n As Integer = d.Byte(p + 1)
		    If n = 0 Then n = 256
		    p = p + 2
		    Var j As Integer = 0
		    While j < n And color < 256 And e - p >= 3 // fix: the colour index moves past each packet
		      For k As Integer = 0 To 2
		        Var v As Integer = d.Byte(p + k)
		        If sixBit Then
		          v = v And 63
		          v = Bitwise.ShiftLeft(v, 2) Or Bitwise.ShiftRight(v, 4)
		        End If
		        pal.Byte(3 * color + k) = v
		      Next
		      j = j + 1
		      color = color + 1
		      p = p + 3
		    Wend
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Sub DoBrun(d As MemoryBlock, p As Integer, e As Integer, px As MemoryBlock, w As Integer, h As Integer)
		  #Pragma DisableBackgroundTasks
		  For y As Integer = 0 To h - 1
		    If p >= e Then Return
		    p = p + 1 // the old packet count: ignored (FLC spec)
		    Var x As Integer = 0
		    Var row As Integer = y * w
		    While x < w And p < e
		      Var n As Integer = d.Int8Value(p)
		      p = p + 1
		      If n > 0 Then // repeat the next byte n times
		        If p >= e Then Return
		        Var v As Integer = d.Byte(p)
		        While n > 0 And x < w
		          px.Byte(row + x) = v
		          x = x + 1
		          n = n - 1
		        Wend
		        p = p + 1
		      ElseIf n < 0 Then // copy -n bytes
		        n = -n
		        While n > 0 And x < w And p < e
		          px.Byte(row + x) = d.Byte(p)
		          x = x + 1
		          p = p + 1
		          n = n - 1
		        Wend
		      End If
		    Wend
		  Next
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Sub DoLC(d As MemoryBlock, p As Integer, e As Integer, px As MemoryBlock, w As Integer, h As Integer)
		  #Pragma DisableBackgroundTasks
		  If e - p < 4 Then Return
		  Var y As Integer = d.UInt16Value(p)
		  Var nlines As Integer = d.UInt16Value(p + 2)
		  p = p + 4
		  While nlines > 0 And y < h And p < e
		    Var npackets As Integer = d.Byte(p)
		    p = p + 1
		    Var x As Integer = 0
		    Var row As Integer = y * w
		    While npackets > 0 And e - p >= 2
		      npackets = npackets - 1
		      x = x + d.Byte(p)
		      Var n As Integer = d.Int8Value(p + 1)
		      p = p + 2
		      If n > 0 Then // copy n bytes
		        While n > 0 And p < e
		          If x < w Then px.Byte(row + x) = d.Byte(p)
		          x = x + 1
		          p = p + 1
		          n = n - 1
		        Wend
		      ElseIf n < 0 Then // repeat the next byte -n times
		        If p >= e Then Return
		        Var v As Integer = d.Byte(p)
		        n = -n
		        While n > 0
		          If x < w Then px.Byte(row + x) = v
		          x = x + 1
		          n = n - 1
		        Wend
		        p = p + 1
		      End If
		    Wend
		    nlines = nlines - 1
		    y = y + 1
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Sub DoSS2(d As MemoryBlock, p As Integer, e As Integer, px As MemoryBlock, w As Integer, h As Integer)
		  #Pragma DisableBackgroundTasks
		  If e - p < 2 Then Return
		  Var nlines As Integer = d.UInt16Value(p)
		  p = p + 2
		  Var y As Integer = 0
		  While nlines > 0 And e - p >= 2 And y < h
		    Var wrd As Integer = d.UInt16Value(p)
		    p = p + 2
		    Var top As Integer = wrd And &hC000
		    If top = &hC000 Then // line skip: -word lines
		      y = y - d.Int16Value(p - 2)
		      Continue While
		    End If
		    If top = &h8000 Then // last byte of this line, then the packet count
		      px.Byte(y * w + w - 1) = wrd And &hFF
		      If e - p < 2 Then Return
		      wrd = d.UInt16Value(p)
		      p = p + 2
		      If (wrd And &hC000) <> 0 Then Return // malformed
		    End If
		    If (wrd And &hC000) = &h4000 Then Continue While // undefined: skip it
		    Var npackets As Integer = wrd
		    nlines = nlines - 1
		    Var x As Integer = 0
		    Var row As Integer = y * w
		    While npackets > 0 And e - p >= 2
		      npackets = npackets - 1
		      x = x + d.Byte(p) // column skip, in bytes
		      Var n As Integer = d.Int8Value(p + 1)
		      p = p + 2
		      If n >= 0 Then // copy n words
		        While n > 0 And e - p >= 2
		          If x < w Then px.Byte(row + x) = d.Byte(p)
		          If x + 1 < w Then px.Byte(row + x + 1) = d.Byte(p + 1)
		          x = x + 2
		          p = p + 2
		          n = n - 1
		        Wend
		      Else // repeat the next word -n times
		        If e - p < 2 Then Return
		        Var b0 As Integer = d.Byte(p)
		        Var b1 As Integer = d.Byte(p + 1)
		        n = -n
		        While n > 0
		          If x < w Then px.Byte(row + x) = b0
		          If x + 1 < w Then px.Byte(row + x + 1) = b1
		          x = x + 2
		          n = n - 1
		        Wend
		        p = p + 2
		      End If
		    Wend
		    y = y + 1
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function WriteFLC(path As String, ByRef err As String) As Boolean
		  #Pragma DisableBackgroundTasks
		  If Frames.Count < 1 Or Width <= 0 Or Height <= 0 Or Frames.Count > 65535 Then
		    err = "nothing to write"
		    Return False
		  End If
		  mOut = New MemoryBlock(65536)
		  mOut.LittleEndian = True
		  mN = 0
		  // 128-byte header (layout of Brian's Fli_head)
		  Put32(0) // size, filled in at the end
		  Put16(kFLCMagic)
		  Put16(Frames.Count)
		  Put16(Width)
		  Put16(Height)
		  Put16(8) // bits a pixel
		  Put16(3) // flags: written and closed properly
		  Put32(DelayMs)
		  While mN < 80
		    Put8(0) // reserved, created/creator/updated/updater, aspect (set below), reserved2
		  Wend
		  mOut.UInt16Value(38) = 1 // aspect x
		  mOut.UInt16Value(40) = 1 // aspect y
		  Put32(128) // oframe1
		  Put32(0) // oframe2, filled in below
		  While mN < 128
		    Put8(0)
		  Wend
		  Var frame2At As Integer
		  For i As Integer = 0 To Frames.LastIndex
		    If i = 1 Then frame2At = mN
		    If i = 0 Then
		      EncFrame(Nil, Nil, Frames(0))
		    Else
		      EncFrame(Frames(i - 1).Pixels, Frames(i - 1).Palette, Frames(i))
		    End If
		  Next
		  If Frames.Count = 1 Then frame2At = mN
		  EncFrame(Frames(Frames.LastIndex).Pixels, Frames(Frames.LastIndex).Palette, Frames(0)) // the ring frame
		  mOut.UInt32Value(0) = mN
		  mOut.UInt32Value(84) = frame2At
		  Try
		    Var bs As BinaryStream = BinaryStream.Create(New FolderItem(path, FolderItem.PathModes.Native), True)
		    bs.Write(mOut.StringValue(0, mN))
		    bs.Close
		  Catch e As RuntimeException
		    err = "cannot write the file"
		    Return False
		  End Try
		  mOut = Nil
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub EncFrame(prevPx As MemoryBlock, prevPal As MemoryBlock, fr As FLIFrame)
		  // COLOR_256 if the palette changed, then the picture as BYTE_RUN (first frame) or a delta
		  Var frameAt As Integer = mN
		  Var chunks As Integer = 0
		  Put32(0)
		  Put16(&hF1FA)
		  Put16(0)
		  Put32(0)
		  Put32(0)
		  Var palChanged As Boolean = (prevPal = Nil)
		  If Not palChanged Then palChanged = (StrComp(prevPal.StringValue(0, 768), fr.Palette.StringValue(0, 768), 0) <> 0) // binary: = on Strings ignores case
		  If palChanged Then
		    Var chunkAt As Integer = mN
		    Put32(0)
		    Put16(4) // COLOR_256
		    Put16(1) // one packet: skip 0, 256 colours
		    Put8(0)
		    Put8(0)
		    PutBytes(fr.Palette, 0, 768)
		    mOut.UInt32Value(chunkAt) = mN - chunkAt
		    chunks = chunks + 1
		  End If
		  Var chunkAt2 As Integer = mN
		  If prevPx = Nil Then
		    Put32(0)
		    Put16(15) // BYTE_RUN
		    EncBrun(fr.Pixels)
		    If (mN - chunkAt2) Mod 2 = 1 Then Put8(0) // keep chunks an even length
		    mOut.UInt32Value(chunkAt2) = mN - chunkAt2
		    chunks = chunks + 1
		  Else
		    Var odd As Boolean = (Width Mod 2 = 1)
		    Put32(0)
		    If odd Then Put16(12) Else Put16(7) // LC for odd widths, SS2 otherwise
		    Var lines As Integer
		    If odd Then lines = EncLC(prevPx, fr.Pixels) Else lines = EncSS2(prevPx, fr.Pixels)
		    If lines = 0 Then
		      mN = chunkAt2 // nothing changed: no chunk at all
		    Else
		      If (mN - chunkAt2) Mod 2 = 1 Then Put8(0)
		      mOut.UInt32Value(chunkAt2) = mN - chunkAt2
		      chunks = chunks + 1
		    End If
		  End If
		  mOut.UInt32Value(frameAt) = mN - frameAt
		  mOut.UInt16Value(frameAt + 6) = chunks
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub EncBrun(px As MemoryBlock)
		  // BYTE_RUN: per line an (obsolete) packet count, then runs (n > 0: repeat) or literals (n < 0: copy)
		  #Pragma DisableBackgroundTasks
		  For y As Integer = 0 To Height - 1
		    Var row As Integer = y * Width
		    Var countAt As Integer = mN
		    Var x, packets As Integer
		    Put8(0)
		    While x < Width
		      Var run As Integer = 1
		      While x + run < Width And run < 127 And px.Byte(row + x + run) = px.Byte(row + x)
		        run = run + 1
		      Wend
		      If run >= 3 Or x + run = Width Then
		        Put8(run)
		        Put8(px.Byte(row + x))
		        x = x + run
		      Else
		        Var start As Integer = x
		        Var lit As Integer = 0
		        While x < Width And lit < 127
		          If x + 2 < Width Then
		            If px.Byte(row + x) = px.Byte(row + x + 1) And px.Byte(row + x) = px.Byte(row + x + 2) Then Exit While
		          End If
		          x = x + 1
		          lit = lit + 1
		        Wend
		        Put8(256 - lit)
		        PutBytes(px, row + start, lit)
		      End If
		      packets = packets + 1
		    Wend
		    mOut.Byte(countAt) = Min(packets, 255)
		  Next
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EncSS2(prv As MemoryBlock, cur As MemoryBlock) As Integer
		  // DELTA_FLC (SS2): word-oriented differences. Returns the lines written; 0 = the same.
		  #Pragma DisableBackgroundTasks
		  Var lines, skip As Integer
		  Var words As Integer = Width \ 2
		  Var linesAt As Integer = mN
		  Put16(0)
		  For y As Integer = 0 To Height - 1
		    Var row As Integer = y * Width
		    If StrComp(prv.StringValue(row, Width), cur.StringValue(row, Width), 0) = 0 Then // binary compare
		      skip = skip + 1
		      Continue For
		    End If
		    While skip > 0 // line skip words: -n
		      Var k As Integer = Min(skip, 16384)
		      Put16(65536 - k)
		      skip = skip - k
		    Wend
		    Var countAt As Integer = mN
		    Put16(0)
		    Var wi, packets As Integer
		    While wi < words
		      Var gap As Integer = 0
		      While wi < words
		        If prv.UInt16Value(row + 2 * wi) <> cur.UInt16Value(row + 2 * wi) Then Exit While
		        wi = wi + 1
		        gap = gap + 1
		      Wend
		      If wi >= words Then Exit While
		      While gap * 2 > 254 // the column skip is one byte: empty packets
		        Put8(254)
		        Put8(0)
		        packets = packets + 1
		        gap = gap - 127
		      Wend
		      Var wv As Integer = cur.UInt16Value(row + 2 * wi)
		      Var rep As Integer = 1
		      While wi + rep < words And rep < 127
		        If cur.UInt16Value(row + 2 * (wi + rep)) <> wv Then Exit While
		        rep = rep + 1
		      Wend
		      Put8(gap * 2)
		      If rep >= 3 Then
		        Put8(256 - rep)
		        Put8(cur.Byte(row + 2 * wi))
		        Put8(cur.Byte(row + 2 * wi + 1))
		        wi = wi + rep
		      Else
		        Var start As Integer = wi
		        Var n As Integer = 0
		        While wi < words And n < 127
		          If prv.UInt16Value(row + 2 * wi) = cur.UInt16Value(row + 2 * wi) Then Exit While
		          If n > 0 And wi + 2 < words Then
		            Var v As Integer = cur.UInt16Value(row + 2 * wi)
		            If cur.UInt16Value(row + 2 * wi + 2) = v And cur.UInt16Value(row + 2 * wi + 4) = v Then Exit While
		          End If
		          wi = wi + 1
		          n = n + 1
		        Wend
		        Put8(n)
		        PutBytes(cur, row + 2 * start, 2 * n)
		      End If
		      packets = packets + 1
		    Wend
		    mOut.UInt16Value(countAt) = packets And &h3FFF
		    lines = lines + 1
		  Next
		  mOut.UInt16Value(linesAt) = lines
		  Return lines
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EncLC(prv As MemoryBlock, cur As MemoryBlock) As Integer
		  // DELTA_FLI (LC): byte-oriented differences, for odd widths. Returns the lines; 0 = the same.
		  #Pragma DisableBackgroundTasks
		  Var first As Integer = -1
		  Var last As Integer = -1
		  For y As Integer = 0 To Height - 1
		    If StrComp(prv.StringValue(y * Width, Width), cur.StringValue(y * Width, Width), 0) <> 0 Then // binary compare
		      If first < 0 Then first = y
		      last = y
		    End If
		  Next
		  If first < 0 Then Return 0
		  Put16(first) // lines to skip
		  Put16(last - first + 1) // lines that follow
		  For y As Integer = first To last
		    Var row As Integer = y * Width
		    Var countAt As Integer = mN
		    Var x, packets As Integer
		    Put8(0)
		    While x < Width
		      Var gap As Integer = 0
		      While x < Width And packets < 250
		        If prv.Byte(row + x) <> cur.Byte(row + x) Then Exit While
		        x = x + 1
		        gap = gap + 1
		      Wend
		      If x >= Width Then Exit While
		      While gap > 255 // the skip is one byte: empty packets
		        Put8(255)
		        Put8(0)
		        packets = packets + 1
		        gap = gap - 255
		      Wend
		      Put8(gap)
		      Var v As Integer = cur.Byte(row + x)
		      Var rep As Integer = 1
		      While x + rep < Width And rep < 127
		        If cur.Byte(row + x + rep) <> v Then Exit While
		        rep = rep + 1
		      Wend
		      If rep >= 3 Then
		        Put8(256 - rep) // negative: repeat one byte
		        Put8(v)
		        x = x + rep
		      Else // positive: copy bytes; after 250 packets, copy the rest
		        Var start As Integer = x
		        Var n As Integer = 0
		        While x < Width And n < 127
		          If packets < 250 And prv.Byte(row + x) = cur.Byte(row + x) Then Exit While
		          If packets < 250 And n > 0 And x + 2 < Width Then
		            If cur.Byte(row + x) = cur.Byte(row + x + 1) And cur.Byte(row + x) = cur.Byte(row + x + 2) Then Exit While
		          End If
		          x = x + 1
		          n = n + 1
		        Wend
		        Put8(n)
		        PutBytes(cur, row + start, n)
		      End If
		      packets = packets + 1
		    Wend
		    mOut.Byte(countAt) = packets
		  Next
		  Return last - first + 1
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Put8(v As Integer)
		  Grow(1)
		  mOut.Byte(mN) = v And 255
		  mN = mN + 1
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Put16(v As Integer)
		  Grow(2)
		  mOut.UInt16Value(mN) = v And &hFFFF
		  mN = mN + 2
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Put32(v As Integer)
		  Grow(4)
		  mOut.UInt32Value(mN) = v
		  mN = mN + 4
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub PutBytes(src As MemoryBlock, offset As Integer, n As Integer)
		  If n <= 0 Then Return
		  Grow(n)
		  mOut.StringValue(mN, n) = src.StringValue(offset, n)
		  mN = mN + n
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Grow(n As Integer)
		  While mN + n > mOut.Size
		    mOut.Size = mOut.Size * 2
		  Wend
		End Sub
	#tag EndMethod

	#tag Property, Flags = &h0
		DelayMs As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Frames() As FLIFrame
	#tag EndProperty

	#tag Property, Flags = &h0
		Height As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mN As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mOut As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h0
		Type As Integer
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
