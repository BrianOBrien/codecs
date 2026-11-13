#tag Class
Protected Class GIFStepper
	#tag Note, Name = About
		Plays a GIFFile one frame at a time, the way a viewer shows it (same rules as
		GIFFile.Composite), without re-drawing from the first frame each time. After StepFrame,
		Canvas (Width*Height RGBA) shows frame NextFrame - 1.
	#tag EndNote

	#tag Method, Flags = &h0
		Sub Constructor(g As GIFFile)
		  mG = g
		  Var n As Integer = g.Width * g.Height * 4
		  Canvas = New MemoryBlock(Max(1, n))
		  mSaved = New MemoryBlock(Max(1, n))
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub StepFrame()
		  #Pragma DisableBackgroundTasks
		  #Pragma BoundsChecking False
		  Var i As Integer = NextFrame
		  NextFrame = NextFrame + 1
		  Var g As GIFFile = mG
		  Var f As GIFFrame = g.Frames(i)
		  Var pal As MemoryBlock = f.Palette
		  Var ncol As Integer = f.NColors
		  If ncol = 0 Then
		    pal = g.Palette
		    ncol = g.NColors
		  End If
		  Var n As Integer = g.Width * g.Height * 4
		  If i > 0 Then // the previous frame's disposal
		    Var p As GIFFrame = g.Frames(i - 1)
		    If p.Disposal = 2 Then
		      For y As Integer = p.Top To Min(p.Top + p.Height, g.Height) - 1
		        For x As Integer = p.Left To Min(p.Left + p.Width, g.Width) - 1
		          Canvas.UInt32Value((y * g.Width + x) * 4) = 0
		        Next
		      Next
		    ElseIf p.Disposal = 3 Then
		      Canvas.StringValue(0, n) = mSaved.StringValue(0, n)
		    End If
		  End If
		  If f.Disposal = 3 Then mSaved.StringValue(0, n) = Canvas.StringValue(0, n)
		  For y As Integer = 0 To f.Height - 1
		    Var cy As Integer = f.Top + y
		    If cy >= g.Height Then Exit For
		    For x As Integer = 0 To f.Width - 1
		      Var cx As Integer = f.Left + x
		      If cx >= g.Width Then Exit For
		      Var idx As Integer = f.Pixels.Byte(y * f.Width + x)
		      If idx = f.Transparent Then Continue For
		      Var px As Integer = (cy * g.Width + cx) * 4
		      If idx < ncol Then
		        Canvas.Byte(px) = pal.Byte(3 * idx)
		        Canvas.Byte(px + 1) = pal.Byte(3 * idx + 1)
		        Canvas.Byte(px + 2) = pal.Byte(3 * idx + 2)
		      Else
		        Canvas.Byte(px) = 0
		        Canvas.Byte(px + 1) = 0
		        Canvas.Byte(px + 2) = 0
		      End If
		      Canvas.Byte(px + 3) = 255
		    Next
		  Next
		End Sub
	#tag EndMethod

	#tag Property, Flags = &h0
		Canvas As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mG As GIFFile
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mSaved As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h0
		NextFrame As Integer
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
		#tag ViewProperty
			Name="NextFrame"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
