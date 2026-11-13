#tag Module
Protected Module GIFOptimizer
	#tag Note, Name = About
		Lossless GIF optimizer, the Xojo port of c/gifopt.c (same choices, same bytes out).

		Every frame is rendered the way a viewer shows it, then re-cut against what is already on the
		screen: only the rectangle that changed is stored; inside it, pixels that did not change may
		become transparent when that encodes smaller; one exact global palette when the animation has
		256 colours or fewer, else a small local palette per frame; identical frames are merged (their
		delays added); disposal 2 is used when pixels must go back to transparent.

		Optimize(g, err) returns a new GIFFile, or Nil with err set.
	#tag EndNote

	#tag Method, Flags = &h0
		Function Optimize(src As GIFFile, ByRef err As String) As GIFFile
		  #Pragma DisableBackgroundTasks
		  #Pragma BoundsChecking False
		  err = ""
		  If src = Nil Or src.Frames.Count = 0 Then
		    err = "empty file"
		    Return Nil
		  End If
		  mW = src.Width
		  mH = src.Height
		  Var n As Integer = mW * mH * 4

		  // pass 1: every colour shown; one global palette if there are 256 or fewer
		  mGMap = New Dictionary
		  mGPal = New MemoryBlock(768)
		  mGlobal = True
		  Var st As New GIFStepper(src)
		  For i As Integer = 0 To src.Frames.LastIndex
		    st.StepFrame
		    Var cv As MemoryBlock = st.Canvas
		    For k As Integer = 0 To n - 4 Step 4
		      If cv.Byte(k + 3) <> 0 Then
		        Var key As Integer = cv.Byte(k) * 65536 + cv.Byte(k + 1) * 256 + cv.Byte(k + 2)
		        If Not mGMap.HasKey(key) Then
		          If mGMap.KeyCount >= 256 Then
		            mGlobal = False
		            Exit For
		          End If
		          Var v As Integer = mGMap.KeyCount
		          mGMap.Value(key) = v
		          mGPal.Byte(3 * v) = cv.Byte(k)
		          mGPal.Byte(3 * v + 1) = cv.Byte(k + 1)
		          mGPal.Byte(3 * v + 2) = cv.Byte(k + 2)
		        End If
		      End If
		    Next
		    If Not mGlobal Then Exit For
		  Next

		  Var g As New GIFFile
		  g.Width = src.Width
		  g.Height = src.Height
		  g.Version89 = True
		  g.LoopCount = src.LoopCount
		  If mGlobal Then
		    Var count As Integer = Max(1, mGMap.KeyCount)
		    mGSlots = Bitwise.ShiftLeft(1, BitsOf(count))
		    g.NColors = mGSlots
		    g.Palette = New MemoryBlock(768)
		    g.Palette.StringValue(0, 768) = mGPal.StringValue(0, 768)
		  End If

		  // pass 2: the frames
		  Var P As New MemoryBlock(n)
		  Var Tprev As New MemoryBlock(n)
		  Var Pprev As New MemoryBlock(n)
		  st = New GIFStepper(src)
		  For i As Integer = 0 To src.Frames.LastIndex
		    st.StepFrame
		    Var T As MemoryBlock = st.Canvas
		    If g.Frames.Count = 0 Then
		      P = New MemoryBlock(n)
		    Else
		      Var last As GIFFrame = g.Frames(g.Frames.LastIndex)
		      P.StringValue(0, n) = Tprev.StringValue(0, n) // the last frame left on screen
		      Var needClear As Boolean = False
		      For k As Integer = 0 To n - 4 Step 4
		        If T.Byte(k + 3) = 0 And P.Byte(k + 3) <> 0 Then
		          needClear = True
		          Exit For
		        End If
		      Next
		      If needClear Then
		        // first try: clear the last frame's rectangle afterwards
		        For y As Integer = last.Top To last.Top + last.Height - 1
		          For x As Integer = last.Left To last.Left + last.Width - 1
		            P.UInt32Value((y * mW + x) * 4) = 0
		          Next
		        Next
		        Var still As Boolean = False
		        For k As Integer = 0 To n - 4 Step 4
		          If T.Byte(k + 3) = 0 And P.Byte(k + 3) <> 0 Then
		            still = True
		            Exit For
		          End If
		        Next
		        If still Then
		          // else: redo the last frame over the whole screen, then clear all of it
		          Var redo As GIFFrame = MakeFrame(Tprev, Pprev, True)
		          If redo = Nil Then
		            err = "a frame needs more than 255 colours plus transparency"
		            Return Nil
		          End If
		          redo.Delay = last.Delay
		          g.Frames(g.Frames.LastIndex) = redo
		          last = redo
		          P = New MemoryBlock(n)
		        End If
		        last.Disposal = 2
		      Else
		        Var changed As Boolean = False
		        For k As Integer = 0 To n - 4 Step 4
		          If Not Same(T, P, k) Then
		            changed = True
		            Exit For
		          End If
		        Next
		        If Not changed Then // identical to the last frame: merge
		          last.Delay = last.Delay + src.Frames(i).Delay
		          Continue For
		        End If
		      End If
		    End If
		    Var f As GIFFrame = MakeFrame(T, P, False)
		    If f = Nil Then
		      err = "a frame needs more than 255 colours plus transparency"
		      Return Nil
		    End If
		    f.Delay = src.Frames(i).Delay
		    f.Disposal = 1
		    g.Frames.Add(f)
		    Pprev.StringValue(0, n) = P.StringValue(0, n)
		    Tprev.StringValue(0, n) = T.StringValue(0, n)
		  Next
		  Return g
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function MakeFrame(T As MemoryBlock, P As MemoryBlock, whole As Boolean) As GIFFrame
		  // the frame that turns screen P into screen T: the changed rectangle (or the whole screen),
		  // cut whichever way is smaller (unchanged pixels kept, or made transparent)
		  #Pragma DisableBackgroundTasks
		  #Pragma BoundsChecking False
		  Var x0 As Integer = mW
		  Var y0 As Integer = mH
		  Var x1 As Integer = -1
		  Var y1 As Integer = -1
		  If whole Then
		    x0 = 0
		    y0 = 0
		    x1 = mW - 1
		    y1 = mH - 1
		  Else
		    For y As Integer = 0 To mH - 1
		      For x As Integer = 0 To mW - 1
		        If Not Same(T, P, (y * mW + x) * 4) Then
		          If x < x0 Then x0 = x
		          If x > x1 Then x1 = x
		          If y < y0 Then y0 = y
		          If y > y1 Then y1 = y
		        End If
		      Next
		    Next
		  End If
		  If x1 < 0 Then // nothing to draw: one transparent pixel
		    x0 = 0
		    x1 = 0
		    y0 = 0
		    y1 = 0
		  End If
		  Var best As GIFFrame
		  Var bestCost As Integer = -1
		  For m As Integer = 0 To 1
		    Var cand As GIFFrame
		    Var c As Integer = TryCut(T, P, x0, y0, x1 - x0 + 1, y1 - y0 + 1, m, cand)
		    If c < 0 Then Continue For
		    If bestCost < 0 Or c < bestCost Then
		      best = cand
		      bestCost = c
		    End If
		  Next
		  Return best
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function TryCut(T As MemoryBlock, P As MemoryBlock, L As Integer, Tp As Integer, W As Integer, H As Integer, mode As Integer, ByRef f As GIFFrame) As Integer
		  // mode 0: unchanged pixels keep their colour; 1: they become transparent. Returns the cost in
		  // bytes and fills f, or -1.
		  #Pragma DisableBackgroundTasks
		  #Pragma BoundsChecking False
		  Var localMap As New Dictionary
		  Var localPal As New MemoryBlock(768)
		  Var used(255) As Boolean
		  Var needT As Boolean = False
		  // pass 1: which colours are written, and is a transparent index needed
		  For y As Integer = 0 To H - 1
		    For x As Integer = 0 To W - 1
		      Var k As Integer = ((Tp + y) * mW + L + x) * 4
		      Var keep As Boolean = (mode = 1) And Same(T, P, k)
		      If keep Or T.Byte(k + 3) = 0 Then
		        needT = True
		        Continue For
		      End If
		      Var key As Integer = T.Byte(k) * 65536 + T.Byte(k + 1) * 256 + T.Byte(k + 2)
		      If mGlobal Then
		        used(mGMap.Value(key).IntegerValue) = True
		      ElseIf Not localMap.HasKey(key) Then
		        If localMap.KeyCount >= 256 Then Return -1
		        Var v As Integer = localMap.KeyCount
		        localMap.Value(key) = v
		        localPal.Byte(3 * v) = T.Byte(k)
		        localPal.Byte(3 * v + 1) = T.Byte(k + 1)
		        localPal.Byte(3 * v + 2) = T.Byte(k + 2)
		      End If
		    Next
		  Next
		  Var trans As Integer = -1
		  Var ncol As Integer
		  If mGlobal Then
		    ncol = mGSlots
		    If needT Then
		      For s As Integer = 0 To mGSlots - 1
		        If Not used(s) Then
		          trans = s
		          Exit For
		        End If
		      Next
		      If trans < 0 Then Return -1
		    End If
		  Else
		    If needT Then
		      If localMap.KeyCount >= 256 Then Return -1
		      trans = localMap.KeyCount
		    End If
		    ncol = localMap.KeyCount
		    If needT Then ncol = ncol + 1
		    If ncol < 1 Then ncol = 1
		  End If
		  // pass 2: the indices
		  Var px As New MemoryBlock(W * H)
		  For y As Integer = 0 To H - 1
		    For x As Integer = 0 To W - 1
		      Var k As Integer = ((Tp + y) * mW + L + x) * 4
		      Var keep As Boolean = (mode = 1) And Same(T, P, k)
		      If keep Or T.Byte(k + 3) = 0 Then
		        px.Byte(y * W + x) = trans
		      Else
		        Var key As Integer = T.Byte(k) * 65536 + T.Byte(k + 1) * 256 + T.Byte(k + 2)
		        If mGlobal Then
		          px.Byte(y * W + x) = mGMap.Value(key).IntegerValue
		        Else
		          px.Byte(y * W + x) = localMap.Value(key).IntegerValue
		        End If
		      End If
		    Next
		  Next
		  Var bits As Integer = BitsOf(ncol)
		  Var codes As MemoryBlock = LZW.GIFEncodeBest(px, W * H, Max(2, bits))
		  If codes = Nil Then Return -1
		  Var clen As Integer = codes.Size
		  Var cost As Integer = clen + clen \ 255 + 1
		  f = New GIFFrame
		  f.Left = L
		  f.Top = Tp
		  f.Width = W
		  f.Height = H
		  f.Transparent = trans
		  f.Pixels = px
		  If Not mGlobal Then
		    f.NColors = ncol
		    f.Palette = localPal
		    cost = cost + Bitwise.ShiftLeft(3, bits)
		  End If
		  Return cost
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Same(a As MemoryBlock, b As MemoryBlock, k As Integer) As Boolean
		  // two screen pixels look the same: both transparent, or both coloured with the same colour
		  If a.Byte(k + 3) = 0 And b.Byte(k + 3) = 0 Then Return True
		  Return a.Byte(k + 3) <> 0 And b.Byte(k + 3) <> 0 And a.Byte(k) = b.Byte(k) And a.Byte(k + 1) = b.Byte(k + 1) And a.Byte(k + 2) = b.Byte(k + 2)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function BitsOf(n As Integer) As Integer
		  Var b As Integer = 1
		  While Bitwise.ShiftLeft(1, b) < n And b < 8
		    b = b + 1
		  Wend
		  Return b
		End Function
	#tag EndMethod

	#tag Property, Flags = &h21
		Private mGlobal As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mGMap As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mGPal As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mGSlots As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mH As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mW As Integer
	#tag EndProperty


	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Module
#tag EndModule
