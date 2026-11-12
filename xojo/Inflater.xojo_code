#tag Class
Protected Class Inflater
	#tag Note, Name = About
		Deflate decoding (TIFF compression 8 and 32946: a zlib stream), ported from inflate.c.
		Deflate = LZ77 back-references (copy LENGTH bytes from DISTANCE back) + Huffman coding.
		Written from RFC 1950/1951, structured like Mark Adler's puff.c: one bit at a time from
		canonical code-length counts. Use: Var n As Integer = New Inflater().Zlib(in, inLen, out, outLen)
	#tag EndNote

	#tag Method, Flags = &h0
		Function Zlib(inp As MemoryBlock, inLen As Integer, out As MemoryBlock, outLen As Integer) As Integer
		  // A zlib stream: 2-byte header, deflate data (Adler-32 not checked).
		  // Returns the bytes written to out, or -1 on corrupt data.
		  If inLen < 2 Then Return -1
		  If (inp.Byte(0) And 15) <> 8 Or (inp.Byte(0) * 256 + inp.Byte(1)) Mod 31 <> 0 Then Return -1
		  If (inp.Byte(1) And &h20) <> 0 Then Return -1 // preset dictionary: not used by TIFF
		  Return Raw(inp, 2, inLen, out, outLen)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Raw(inp As MemoryBlock, start As Integer, inLen As Integer, out As MemoryBlock, outLen As Integer) As Integer
		  mIn = inp
		  mInPos = start
		  mInLen = inLen
		  mBitBuf = 0
		  mBitCnt = 0
		  mOut = out
		  mOutLen = outLen
		  mOutCnt = 0
		  mErr = False
		  mFull = False
		  Var last As Integer
		  Do
		    last = Bits(1)
		    Var blockType As Integer = Bits(2)
		    If mErr Then Exit Do
		    Select Case blockType
		    Case 0
		      Stored
		    Case 1
		      Fixed
		    Case 2
		      Dynamic
		    Else
		      mErr = True
		    End Select
		  Loop Until last = 1 Or mErr Or mFull
		  If mErr And Not mFull Then Return -1
		  Return mOutCnt
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Bits(need As Integer) As Integer
		  // Deflate packs bits least significant first
		  #Pragma DisableBackgroundTasks
		  Var v As Integer = mBitBuf
		  While mBitCnt < need
		    If mInPos >= mInLen Then
		      mErr = True
		      Return 0
		    End If
		    v = v Or Bitwise.ShiftLeft(mIn.Byte(mInPos), mBitCnt)
		    mInPos = mInPos + 1
		    mBitCnt = mBitCnt + 8
		  Wend
		  mBitBuf = Bitwise.ShiftRight(v, need)
		  mBitCnt = mBitCnt - need
		  Return v And (Bitwise.ShiftLeft(1, need) - 1)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub PutByte(c As Integer)
		  If mOutCnt < mOutLen Then
		    mOut.Byte(mOutCnt) = c
		    mOutCnt = mOutCnt + 1
		  Else
		    mFull = True
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Stored()
		  // Block type 0: LEN, NLEN, then LEN raw bytes
		  mBitBuf = 0
		  mBitCnt = 0
		  If mInPos + 4 > mInLen Then
		    mErr = True
		    Return
		  End If
		  Var length As Integer = mIn.Byte(mInPos) + 256 * mIn.Byte(mInPos + 1)
		  Var nlen As Integer = mIn.Byte(mInPos + 2) + 256 * mIn.Byte(mInPos + 3)
		  If nlen <> (65535 - length) Then
		    mErr = True
		    Return
		  End If
		  mInPos = mInPos + 4
		  If mInPos + length > mInLen Then
		    mErr = True
		    Return
		  End If
		  While length > 0 And Not mFull
		    PutByte(mIn.Byte(mInPos))
		    mInPos = mInPos + 1
		    length = length - 1
		  Wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Construct(h As HuffTable, lengths() As Integer, first As Integer, n As Integer) As Integer
		  // Canonical Huffman table from code lengths. <0 over-subscribed, 0 complete, >0 incomplete.
		  Var offs(15) As Integer
		  For bitLen As Integer = 0 To 15
		    h.Count(bitLen) = 0
		  Next
		  For sym As Integer = 0 To n - 1
		    h.Count(lengths(first + sym)) = h.Count(lengths(first + sym)) + 1
		  Next
		  If h.Count(0) = n Then Return 0
		  Var avail As Integer = 1
		  For bitLen As Integer = 1 To 15
		    avail = avail * 2 - h.Count(bitLen)
		    If avail < 0 Then Return avail
		  Next
		  offs(1) = 0
		  For bitLen As Integer = 1 To 14
		    offs(bitLen + 1) = offs(bitLen) + h.Count(bitLen)
		  Next
		  For sym As Integer = 0 To n - 1
		    Var L As Integer = lengths(first + sym)
		    If L <> 0 Then
		      h.Symbol(offs(L)) = sym
		      offs(L) = offs(L) + 1
		    End If
		  Next
		  Return avail
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Decode(h As HuffTable) As Integer
		  // One symbol, one bit at a time
		  #Pragma DisableBackgroundTasks
		  Var code, first, index As Integer
		  For bitLen As Integer = 1 To 15
		    code = code Or Bits(1)
		    If mErr Then Return -1
		    Var count As Integer = h.Count(bitLen)
		    If code - count < first Then Return h.Symbol(index + (code - first))
		    index = index + count
		    first = (first + count) * 2
		    code = code * 2
		  Next
		  mErr = True
		  Return -1
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Codes(lencode As HuffTable, distcode As HuffTable)
		  // Literals and length/distance pairs until end-of-block (256)
		  #Pragma DisableBackgroundTasks
		  Var lbase() As Integer = Array(3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258)
		  Var lext() As Integer = Array(0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0)
		  Var dbase() As Integer = Array(1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577)
		  Var dext() As Integer = Array(0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13)
		  Do
		    Var sym As Integer = Decode(lencode)
		    If mErr Or mFull Then Return
		    If sym < 256 Then
		      PutByte(sym)
		    ElseIf sym = 256 Then
		      Return // end of block
		    Else
		      sym = sym - 257
		      If sym >= 29 Then
		        mErr = True
		        Return
		      End If
		      Var length As Integer = lbase(sym) + Bits(lext(sym))
		      sym = Decode(distcode)
		      If mErr Or sym < 0 Or sym >= 30 Then
		        mErr = True
		        Return
		      End If
		      Var dist As Integer = dbase(sym) + Bits(dext(sym))
		      If mErr Or dist > mOutCnt Then
		        mErr = True // reaches back before the start
		        Return
		      End If
		      While length > 0 And Not mFull // byte by byte: the copy may overlap itself
		        PutByte(mOut.Byte(mOutCnt - dist))
		        length = length - 1
		      Wend
		    End If
		  Loop
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Fixed()
		  // Block type 1: the fixed tables from RFC 1951
		  Var lengths(287) As Integer
		  For sym As Integer = 0 To 287
		    If sym < 144 Then
		      lengths(sym) = 8
		    ElseIf sym < 256 Then
		      lengths(sym) = 9
		    ElseIf sym < 280 Then
		      lengths(sym) = 7
		    Else
		      lengths(sym) = 8
		    End If
		  Next
		  Var lencode As New HuffTable
		  Call Construct(lencode, lengths, 0, 288)
		  Var dl(29) As Integer
		  For sym As Integer = 0 To 29
		    dl(sym) = 5
		  Next
		  Var distcode As New HuffTable
		  Call Construct(distcode, dl, 0, 30)
		  Codes(lencode, distcode)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub Dynamic()
		  // Block type 2: the tables come first, themselves Huffman-coded
		  Var order() As Integer = Array(16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15)
		  Var lengths(315) As Integer
		  Var nlen As Integer = Bits(5) + 257
		  Var ndist As Integer = Bits(5) + 1
		  Var ncode As Integer = Bits(4) + 4
		  If mErr Or nlen > 286 Or ndist > 30 Then
		    mErr = True
		    Return
		  End If
		  For index As Integer = 0 To 18
		    If index < ncode Then
		      lengths(order(index)) = Bits(3)
		    Else
		      lengths(order(index)) = 0
		    End If
		  Next
		  Var lencode As New HuffTable
		  If mErr Or Construct(lencode, lengths, 0, 19) <> 0 Then
		    mErr = True // the code-length code must be complete
		    Return
		  End If
		  Var index As Integer = 0
		  While index < nlen + ndist
		    Var sym As Integer = Decode(lencode)
		    If mErr Then Return
		    If sym < 16 Then
		      lengths(index) = sym
		      index = index + 1
		    Else
		      Var bitLen As Integer = 0
		      Var rep As Integer
		      If sym = 16 Then // repeat the previous length 3-6 times
		        If index = 0 Then
		          mErr = True
		          Return
		        End If
		        bitLen = lengths(index - 1)
		        rep = 3 + Bits(2)
		      ElseIf sym = 17 Then // 3-10 zeros
		        rep = 3 + Bits(3)
		      Else // 11-138 zeros
		        rep = 11 + Bits(7)
		      End If
		      If mErr Or index + rep > nlen + ndist Then
		        mErr = True
		        Return
		      End If
		      While rep > 0
		        lengths(index) = bitLen
		        index = index + 1
		        rep = rep - 1
		      Wend
		    End If
		  Wend
		  If lengths(256) = 0 Then
		    mErr = True // no end-of-block code
		    Return
		  End If
		  lencode = New HuffTable
		  Var e As Integer = Construct(lencode, lengths, 0, nlen)
		  If e < 0 Or (e > 0 And nlen - lencode.Count(0) <> 1) Then
		    mErr = True
		    Return
		  End If
		  Var distcode As New HuffTable
		  e = Construct(distcode, lengths, nlen, ndist)
		  If e < 0 Or (e > 0 And ndist - distcode.Count(0) <> 1) Then
		    mErr = True
		    Return
		  End If
		  Codes(lencode, distcode)
		End Sub
	#tag EndMethod

	#tag Property, Flags = &h21
		Private mBitBuf As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mBitCnt As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mErr As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mFull As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mIn As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mInLen As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mInPos As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mOut As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mOutCnt As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mOutLen As Integer
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
