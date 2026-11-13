#tag Module
Protected Module Quantizer
	#tag Note, Name = About
		Colour quantizer: weighted k-means in OKLab, the Xojo port of c/quant.c (same palette out).

		Build(rgb, cnt, k, pal, map): rgb() distinct colours (&hRRGGBB) used by cnt() pixels each. Fills
		pal() (at most k colours, each one of the input colours) and map() (the palette entry each input
		colour becomes). Rare colours fold into their neighbours; colours many pixels use stay exact.

		SortKey(rgb): palette order: greys dark to light, then colours by hue (16 sectors), each dark to light.
	#tag EndNote

	#tag Method, Flags = &h1
		Protected Function Build(rgb() As Integer, cnt() As Integer, k As Integer, ByRef pal() As Integer, ByRef map() As Integer) As Integer
		  #Pragma DisableBackgroundTasks
		  #Pragma BoundsChecking False
		  Var n As Integer = rgb.Count
		  pal.RemoveAll
		  map.RemoveAll
		  If n <= 0 Or k <= 0 Then Return 0
		  If n <= k Then // fits already
		    For i As Integer = 0 To n - 1
		      pal.Add(rgb(i))
		      map.Add(i)
		    Next
		    Return n
		  End If
		  Var lab() As Double
		  lab.ResizeTo(3 * n - 1)
		  For i As Integer = 0 To n - 1
		    Var L, a, b As Double
		    OKLab(rgb(i), L, a, b)
		    lab(3 * i) = L
		    lab(3 * i + 1) = a
		    lab(3 * i + 2) = b
		  Next

		  // start: the most used colour, then the largest count x distance^2
		  Var cen() As Double
		  cen.ResizeTo(3 * k - 1)
		  Var j As Integer = 0
		  For i As Integer = 1 To n - 1
		    If cnt(i) > cnt(j) Then j = i
		  Next
		  cen(0) = lab(3 * j)
		  cen(1) = lab(3 * j + 1)
		  cen(2) = lab(3 * j + 2)
		  Var nc As Integer = 1
		  Var best() As Double
		  best.ResizeTo(n - 1)
		  For i As Integer = 0 To n - 1
		    best(i) = D2(lab, 3 * i, cen, 0)
		  Next
		  While nc < k
		    Var top As Double = 0
		    j = -1
		    For i As Integer = 0 To n - 1
		      Var v As Double = cnt(i) * best(i)
		      If v > top Then
		        top = v
		        j = i
		      End If
		    Next
		    If j < 0 Then Exit While
		    cen(3 * nc) = lab(3 * j)
		    cen(3 * nc + 1) = lab(3 * j + 1)
		    cen(3 * nc + 2) = lab(3 * j + 2)
		    For i As Integer = 0 To n - 1
		      Var v As Double = D2(lab, 3 * i, cen, 3 * nc)
		      If v < best(i) Then best(i) = v
		    Next
		    nc = nc + 1
		  Wend

		  // Lloyd iterations
		  Var asg() As Integer
		  asg.ResizeTo(n - 1)
		  For i As Integer = 0 To n - 1
		    asg(i) = -1
		  Next
		  For iter As Integer = 0 To 15
		    Var changed As Boolean = False
		    Var sum() As Double
		    sum.ResizeTo(4 * nc - 1)
		    For i As Integer = 0 To n - 1
		      Var bc As Integer = 0
		      Var bd As Double = D2(lab, 3 * i, cen, 0)
		      For c As Integer = 1 To nc - 1
		        Var v As Double = D2(lab, 3 * i, cen, 3 * c)
		        If v < bd Then
		          bd = v
		          bc = c
		        End If
		      Next
		      If asg(i) <> bc Then changed = True
		      asg(i) = bc
		      sum(4 * bc) = sum(4 * bc) + cnt(i) * lab(3 * i)
		      sum(4 * bc + 1) = sum(4 * bc + 1) + cnt(i) * lab(3 * i + 1)
		      sum(4 * bc + 2) = sum(4 * bc + 2) + cnt(i) * lab(3 * i + 2)
		      sum(4 * bc + 3) = sum(4 * bc + 3) + cnt(i)
		    Next
		    For c As Integer = 0 To nc - 1
		      If sum(4 * c + 3) > 0 Then
		        cen(3 * c) = sum(4 * c) / sum(4 * c + 3)
		        cen(3 * c + 1) = sum(4 * c + 1) / sum(4 * c + 3)
		        cen(3 * c + 2) = sum(4 * c + 2) / sum(4 * c + 3)
		      End If
		    Next
		    If Not changed Then Exit For
		  Next

		  // each cluster becomes its member nearest the centre (ties: more pixels, then first)
		  map.ResizeTo(n - 1)
		  For c As Integer = 0 To nc - 1
		    Var rep As Integer = -1
		    Var rd As Double = 0
		    For i As Integer = 0 To n - 1
		      If asg(i) = c Then
		        Var v As Double = D2(lab, 3 * i, cen, 3 * c)
		        If rep < 0 Or v < rd Or (v = rd And cnt(i) > cnt(rep)) Then
		          rep = i
		          rd = v
		        End If
		      End If
		    Next
		    If rep < 0 Then Continue For // an empty cluster: dropped
		    Var m As Integer = pal.Count
		    pal.Add(rgb(rep))
		    For i As Integer = 0 To n - 1
		      If asg(i) = c Then map(i) = m
		    Next
		  Next
		  Return pal.Count
		End Function
	#tag EndMethod

	#tag Method, Flags = &h1
		Protected Function SortKey(rgb As Integer) As UInt64
		  Var r As Integer = Bitwise.ShiftRight(rgb, 16) And 255
		  Var g As Integer = Bitwise.ShiftRight(rgb, 8) And 255
		  Var b As Integer = rgb And 255
		  Var mx As Integer = Max(r, g, b)
		  Var mn As Integer = Min(r, g, b)
		  Var luma As UInt64 = r * 299 + g * 587 + b * 114
		  Var group As UInt64 = 0
		  If mx - mn >= 12 Then // a colour, not a grey: 16 hue sectors
		    Var d As Integer = mx - mn
		    Var h As Integer
		    If mx = r Then
		      h = (g - b) * 256 \ d
		    ElseIf mx = g Then
		      h = 512 + (b - r) * 256 \ d
		    Else
		      h = 1024 + (r - g) * 256 \ d
		    End If
		    If h < 0 Then h = h + 1536
		    group = 1 + h \ 96
		  End If
		  Return Bitwise.ShiftLeft(group, 42) Or Bitwise.ShiftLeft(luma, 24) Or CType(rgb, UInt64)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function D2(p() As Double, i As Integer, q() As Double, j As Integer) As Double
		  Var x As Double = p(i) - q(j)
		  Var y As Double = p(i + 1) - q(j + 1)
		  Var z As Double = p(i + 2) - q(j + 2)
		  Return x * x + y * y + z * z
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function Lin(c As Integer) As Double
		  // sRGB 0..255 to linear light
		  Var v As Double = c / 255.0
		  If v <= 0.04045 Then Return v / 12.92
		  Return Pow((v + 0.055) / 1.055, 2.4)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub OKLab(rgb As Integer, ByRef L As Double, ByRef a As Double, ByRef b As Double)
		  Var r As Double = Lin(Bitwise.ShiftRight(rgb, 16) And 255)
		  Var g As Double = Lin(Bitwise.ShiftRight(rgb, 8) And 255)
		  Var bl As Double = Lin(rgb And 255)
		  Var l1 As Double = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl
		  Var m1 As Double = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl
		  Var s1 As Double = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl
		  l1 = Pow(l1, 1.0 / 3.0)
		  m1 = Pow(m1, 1.0 / 3.0)
		  s1 = Pow(s1, 1.0 / 3.0)
		  L = 0.2104542553 * l1 + 0.7936177850 * m1 - 0.0040720468 * s1
		  a = 1.9779984951 * l1 - 2.4285922050 * m1 + 0.4505937099 * s1
		  b = 0.0259040371 * l1 + 0.7827717662 * m1 - 0.8086757660 * s1
		End Sub
	#tag EndMethod


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
