#tag Module
Protected Module PackBits
	#tag Note, Name = About
		PackBits (TIFF compression 32773), TIFF's run-length coding. Header byte n:
		0..127 copy the next n+1 bytes; -127..-1 repeat the next byte 1-n times; -128 skip.
	#tag EndNote

	#tag Method, Flags = &h0
		Function Decode(inp As MemoryBlock, inLen As Integer, out As MemoryBlock, outLen As Integer) As Integer
		  // Returns the bytes written to out, or -1 on corrupt data
		  #Pragma DisableBackgroundTasks
		  Var i, nout As Integer
		  While i < inLen And nout < outLen
		    Var n As Integer = inp.Int8Value(i)
		    i = i + 1
		    If n >= 0 Then
		      If i + n + 1 > inLen Then Return -1
		      For k As Integer = 0 To n
		        If nout >= outLen Then Exit For
		        out.Byte(nout) = inp.Byte(i + k)
		        nout = nout + 1
		      Next
		      i = i + n + 1
		    ElseIf n <> -128 Then
		      If i >= inLen Then Return -1
		      Var b As Integer = inp.Byte(i)
		      For k As Integer = 1 To 1 - n
		        If nout >= outLen Then Exit For
		        out.Byte(nout) = b
		        nout = nout + 1
		      Next
		      i = i + 1
		    End If
		  Wend
		  Return nout
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Encode(inp As MemoryBlock, n As Integer) As MemoryBlock
		  // Runs of 3 or more equal bytes become a repeat; the rest literal runs of up to 128
		  #Pragma DisableBackgroundTasks
		  Var out As New MemoryBlock(n + n \ 128 + 2)
		  Var i, o As Integer
		  While i < n
		    Var run As Integer = 1
		    While i + run < n And run < 128 And inp.Byte(i + run) = inp.Byte(i)
		      run = run + 1
		    Wend
		    If run >= 3 Then
		      out.Int8Value(o) = 1 - run
		      out.Byte(o + 1) = inp.Byte(i)
		      o = o + 2
		      i = i + run
		    Else
		      Var start As Integer = i
		      Var lit As Integer = 0
		      While i < n And lit < 128
		        If i + 2 < n Then
		          If inp.Byte(i) = inp.Byte(i + 1) And inp.Byte(i) = inp.Byte(i + 2) Then Exit While
		        End If
		        i = i + 1
		        lit = lit + 1
		      Wend
		      out.Byte(o) = lit - 1
		      o = o + 1
		      For k As Integer = 0 To lit - 1
		        out.Byte(o + k) = inp.Byte(start + k)
		      Next
		      o = o + lit
		    End If
		  Wend
		  out.Size = o
		  Return out
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
