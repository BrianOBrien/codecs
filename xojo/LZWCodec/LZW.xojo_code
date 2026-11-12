#tag Module
Protected Module LZW
	#tag Note, Name = About
		TIFF LZW (compression 5), ported from lzw.c, which adapts Brian O'Brien's GIF LZW
		(github.com/BrianOBrien/lzw): same string table (prefix + character) and stack.
		TIFF rules: codes most significant bit first, no sub-blocks, early change,
		Clear = 256, EndOfInformation = 257, 9 to 12-bit codes, Clear when the table reaches 4094.
GIFDecode / GIFEncode: the GIF flavour from Brian's Readgif / Writegif (1998-99): least significant
bit first, no early change, Clear = 2^minCodeSize; the 255-byte sub-blocks are handled by GIFFile.
	#tag EndNote

	#tag Constant, Name = kClear, Type = Double, Dynamic = False, Default = \"256", Scope = Public
	#tag EndConstant

	#tag Constant, Name = kEOI, Type = Double, Dynamic = False, Default = \"257", Scope = Public
	#tag EndConstant

	#tag Constant, Name = kFirst, Type = Double, Dynamic = False, Default = \"258", Scope = Public
	#tag EndConstant

	#tag Constant, Name = kTable, Type = Double, Dynamic = False, Default = \"4096", Scope = Public
	#tag EndConstant

	#tag Method, Flags = &h0
		Function Decode(inp As MemoryBlock, inLen As Integer, out As MemoryBlock, outLen As Integer) As Integer
		  // Decode one strip or tile. Returns the bytes written to out, or -1 on corrupt data.
		  //  Read OLD_CODE, output it; then for each NEW_CODE: STRING = its translation (or, if not in
		  //  the table yet, OLD_CODE's + CHARACTER); output STRING; CHARACTER = its first character;
		  //  add OLD_CODE + CHARACTER to the table; OLD_CODE = NEW_CODE.
		  #Pragma DisableBackgroundTasks
		  Var prefix(4095) As Integer
		  Var ch(4095) As Integer
		  Var stack(4095) As Integer
		  For i As Integer = 0 To 255
		    prefix(i) = -1
		    ch(i) = i
		  Next
		  Var inPos, accume, bitsInAccume, nout As Integer
		  Var nEntries As Integer = kFirst
		  Var codeSize As Integer = 9
		  Var oldCode As Integer = -1
		  Var c As Integer = 0
		  Do
		    While bitsInAccume < codeSize // most significant bit first
		      If inPos >= inLen Then Return nout
		      accume = accume * 256 + inp.Byte(inPos)
		      inPos = inPos + 1
		      bitsInAccume = bitsInAccume + 8
		    Wend
		    bitsInAccume = bitsInAccume - codeSize
		    Var newCode As Integer = Bitwise.ShiftRight(accume, bitsInAccume)
		    accume = accume And (Bitwise.ShiftLeft(1, bitsInAccume) - 1)
		  
		    If newCode = kEOI Then Exit Do
		    If newCode = kClear Then
		      nEntries = kFirst
		      codeSize = 9
		      oldCode = -1
		      Continue Do
		    End If
		    If oldCode = -1 Then // first code after a Clear: a root
		      If newCode > 255 Then Return -1
		      If nout < outLen Then
		        out.Byte(nout) = newCode
		        nout = nout + 1
		      End If
		      c = newCode
		      oldCode = newCode
		      Continue Do
		    End If
		  
		    Var sp As Integer = -1
		    Var s As Integer
		    If newCode < nEntries Then
		      s = newCode
		    ElseIf newCode = nEntries Then // KwKwK
		      sp = sp + 1
		      stack(sp) = c
		      s = oldCode
		    Else
		      Return -1 // forward reference: corrupt
		    End If
		    While s <> -1
		      If sp >= 4095 Then Return -1
		      sp = sp + 1
		      stack(sp) = ch(s)
		      s = prefix(s)
		    Wend
		    c = stack(sp) // first character of STRING
		    While sp >= 0
		      If nout < outLen Then
		        out.Byte(nout) = stack(sp)
		        nout = nout + 1
		      End If
		      sp = sp - 1
		    Wend
		    If nEntries < kTable Then
		      prefix(nEntries) = oldCode
		      ch(nEntries) = c
		      nEntries = nEntries + 1
		      If nEntries >= Bitwise.ShiftLeft(1, codeSize) - 1 And codeSize < 12 Then codeSize = codeSize + 1 // early change
		    End If
		    oldCode = newCode
		  Loop
		  Return nout
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Encode(inp As MemoryBlock, n As Integer) As MemoryBlock
		  // Encode one strip or tile. The loop of Brian's lzw::write:
		  //   if Pc is in the table, P = Pc; else output the code for P, add Pc, P = c
		  #Pragma DisableBackgroundTasks
		  Const kHSize = 9001
		  Var htab(9000) As Integer   // key (c << 12) Or P, -1 = empty
		  Var codetab(9000) As Integer
		  For i As Integer = 0 To kHSize - 1
		    htab(i) = -1
		  Next
		  Var out As New MemoryBlock(n \ 2 + 64)
		  Var o, accume, bitsInAccume As Integer
		  Var nbits As Integer = 9
		  Var maxcode As Integer = 511
		  Var freeEnt As Integer = kFirst
		  Var ent As Integer = -1
		  
		  PutCode(out, o, accume, bitsInAccume, kClear, nbits)
		  For k As Integer = 0 To n - 1
		    Var c As Integer = inp.Byte(k)
		    If ent = -1 Then
		      ent = c
		      Continue For
		    End If
		    Var key As Integer = Bitwise.ShiftLeft(c, 12) Or ent
		    Var h As Integer = (Bitwise.ShiftLeft(c, 8) Xor ent) Mod kHSize
		    While htab(h) <> -1 And htab(h) <> key
		      h = (h + 1) Mod kHSize
		    Wend
		    If htab(h) = key Then
		      ent = codetab(h) // P = Pc
		      Continue For
		    End If
		    PutCode(out, o, accume, bitsInAccume, ent, nbits) // output P
		    ent = c
		    htab(h) = key // add Pc
		    codetab(h) = freeEnt
		    freeEnt = freeEnt + 1
		    If freeEnt = kTable - 2 Then // full: Clear and start again
		      PutCode(out, o, accume, bitsInAccume, kClear, nbits)
		      For i As Integer = 0 To kHSize - 1
		        htab(i) = -1
		      Next
		      nbits = 9
		      maxcode = 511
		      freeEnt = kFirst
		    ElseIf freeEnt > maxcode Then // early change, matching the decoder
		      nbits = nbits + 1
		      maxcode = Bitwise.ShiftLeft(1, nbits) - 1
		    End If
		  Next
		  If ent <> -1 Then
		    PutCode(out, o, accume, bitsInAccume, ent, nbits)
		    freeEnt = freeEnt + 1
		    If freeEnt = kTable - 2 Then
		      PutCode(out, o, accume, bitsInAccume, kClear, nbits)
		      nbits = 9
		    ElseIf freeEnt > maxcode Then
		      nbits = nbits + 1
		    End If
		  End If
		  PutCode(out, o, accume, bitsInAccume, kEOI, nbits)
		  If bitsInAccume > 0 Then PutCode(out, o, accume, bitsInAccume, 0, 8 - bitsInAccume) // pad with zeros
		  out.Size = o
		  Return out
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GIFDecode(inp As MemoryBlock, inLen As Integer, minCodeSize As Integer, out As MemoryBlock, outLen As Integer) As Integer
		  // GIF LZW (Brian's lzw_decompress, Readgif 1999): least significant bit first, the width grows
		  // when the table reaches 2^n (no early change). inp holds the code bytes with the sub-blocks removed.
		  // Returns the bytes written to out, or -1 on corrupt data.
		  #Pragma DisableBackgroundTasks
		  If minCodeSize < 2 Or minCodeSize > 8 Then Return -1
		  Var clearCode As Integer = Bitwise.ShiftLeft(1, minCodeSize)
		  Var eofCode As Integer = clearCode + 1
		  Var prefix(4095) As Integer
		  Var ch(4095) As Integer
		  Var stack(4095) As Integer
		  For i As Integer = 0 To clearCode - 1
		    prefix(i) = -1
		    ch(i) = i
		  Next
		  Var inPos, accume, bitsInAccume, nout As Integer
		  Var nEntries As Integer = clearCode + 2
		  Var codeSize As Integer = minCodeSize + 1
		  Var oldCode As Integer = -1
		  Var c As Integer
		  Do
		    While bitsInAccume < codeSize // least significant bit first
		      If inPos >= inLen Then Return nout // many files end without EndOfInformation
		      accume = accume Or Bitwise.ShiftLeft(inp.Byte(inPos), bitsInAccume)
		      inPos = inPos + 1
		      bitsInAccume = bitsInAccume + 8
		    Wend
		    Var newCode As Integer = accume And (Bitwise.ShiftLeft(1, codeSize) - 1)
		    accume = Bitwise.ShiftRight(accume, codeSize)
		    bitsInAccume = bitsInAccume - codeSize
		  
		    If newCode = eofCode Then Exit Do
		    If newCode = clearCode Then
		      nEntries = clearCode + 2
		      codeSize = minCodeSize + 1
		      oldCode = -1
		      Continue Do
		    End If
		    If oldCode = -1 Then
		      If newCode >= clearCode Then Return -1
		      If nout < outLen Then
		        out.Byte(nout) = newCode
		        nout = nout + 1
		      End If
		      c = newCode
		      oldCode = newCode
		      Continue Do
		    End If
		    Var sp As Integer = -1
		    Var s As Integer
		    If newCode < nEntries Then
		      s = newCode
		    ElseIf newCode = nEntries Then // KwKwK
		      sp = sp + 1
		      stack(sp) = c
		      s = oldCode
		    Else
		      Return -1
		    End If
		    While s <> -1
		      If sp >= 4095 Then Return -1
		      sp = sp + 1
		      stack(sp) = ch(s)
		      s = prefix(s)
		    Wend
		    c = stack(sp)
		    While sp >= 0
		      If nout < outLen Then
		        out.Byte(nout) = stack(sp)
		        nout = nout + 1
		      End If
		      sp = sp - 1
		    Wend
		    If nEntries < kTable Then // addcode(old_code, C)
		      prefix(nEntries) = oldCode
		      ch(nEntries) = c
		      nEntries = nEntries + 1
		      If nEntries + 1 > Bitwise.ShiftLeft(1, codeSize) And codeSize < 12 Then codeSize = codeSize + 1
		    End If
		    oldCode = newCode
		  Loop
		  Return nout
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GIFEncode(inp As MemoryBlock, n As Integer, minCodeSize As Integer) As MemoryBlock
		  // GIF LZW (Brian's lzw::write and bitstream::write, Writegif 1998-99) without the sub-blocks:
		  // the width grows in put() once the table has passed 2^n entries; Clear when it reaches 4096.
		  #Pragma DisableBackgroundTasks
		  If minCodeSize < 2 Or minCodeSize > 8 Then Return Nil
		  Const kHSize = 9001
		  Var htab(9000) As Integer
		  Var codetab(9000) As Integer
		  For i As Integer = 0 To kHSize - 1
		    htab(i) = -1
		  Next
		  Var clearCode As Integer = Bitwise.ShiftLeft(1, minCodeSize)
		  Var eofCode As Integer = clearCode + 1
		  Var nEntries As Integer = clearCode + 2
		  Var codeSize As Integer = minCodeSize + 1
		  Var out As New MemoryBlock(n \ 2 + 64)
		  Var o, accume, bitsInAccume As Integer
		  Var prefix As Integer = -1
		  
		  GIFPut(out, o, accume, bitsInAccume, clearCode, codeSize)
		  For k As Integer = 0 To n - 1
		    Var c As Integer = inp.Byte(k) And (clearCode - 1)
		    If prefix = -1 Then
		      prefix = c
		      Continue For
		    End If
		    Var key As Integer = Bitwise.ShiftLeft(c, 12) Or prefix
		    Var h As Integer = (Bitwise.ShiftLeft(c, 8) Xor prefix) Mod kHSize
		    While htab(h) <> -1 And htab(h) <> key
		      h = (h + 1) Mod kHSize
		    Wend
		    If htab(h) = key Then
		      prefix = codetab(h)
		      Continue For
		    End If
		    If nEntries > Bitwise.ShiftLeft(1, codeSize) Then codeSize = codeSize + 1 // put(current.prefix)
		    GIFPut(out, o, accume, bitsInAccume, prefix, codeSize)
		    If nEntries = kTable Then // table full: Clear and start again
		      If nEntries > Bitwise.ShiftLeft(1, codeSize) Then codeSize = codeSize + 1
		      GIFPut(out, o, accume, bitsInAccume, clearCode, codeSize)
		      For i As Integer = 0 To kHSize - 1
		        htab(i) = -1
		      Next
		      nEntries = clearCode + 2
		      codeSize = minCodeSize + 1
		    Else
		      htab(h) = key
		      codetab(h) = nEntries
		      nEntries = nEntries + 1
		    End If
		    prefix = c
		  Next
		  If prefix <> -1 Then
		    If nEntries > Bitwise.ShiftLeft(1, codeSize) Then codeSize = codeSize + 1
		    GIFPut(out, o, accume, bitsInAccume, prefix, codeSize)
		  End If
		  If nEntries > Bitwise.ShiftLeft(1, codeSize) Then codeSize = codeSize + 1
		  GIFPut(out, o, accume, bitsInAccume, eofCode, codeSize)
		  If bitsInAccume > 0 Then GIFPut(out, o, accume, bitsInAccume, 0, 8 - bitsInAccume)
		  out.Size = o
		  Return out
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub GIFPut(out As MemoryBlock, ByRef o As Integer, ByRef accume As Integer, ByRef bitsInAccume As Integer, code As Integer, nbits As Integer)
		  // Least significant bit first (bitstream::write)
		  accume = accume Or Bitwise.ShiftLeft(code, bitsInAccume)
		  bitsInAccume = bitsInAccume + nbits
		  While bitsInAccume >= 8
		    If o >= out.Size Then out.Size = out.Size * 2
		    out.Byte(o) = accume And 255
		    o = o + 1
		    accume = Bitwise.ShiftRight(accume, 8)
		    bitsInAccume = bitsInAccume - 8
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub PutCode(out As MemoryBlock, ByRef o As Integer, ByRef accume As Integer, ByRef bitsInAccume As Integer, code As Integer, nbits As Integer)
		  // Write nbits, most significant bit first (the GIF bitstream::write put the low bits first)
		  accume = Bitwise.ShiftLeft(accume, nbits) Or code
		  bitsInAccume = bitsInAccume + nbits
		  While bitsInAccume >= 8
		    If o >= out.Size Then out.Size = out.Size * 2
		    out.Byte(o) = Bitwise.ShiftRight(accume, bitsInAccume - 8) And 255
		    o = o + 1
		    bitsInAccume = bitsInAccume - 8
		  Wend
		  accume = accume And (Bitwise.ShiftLeft(1, bitsInAccume) - 1)
		End Sub
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
