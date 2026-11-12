#tag Class
Protected Class GIFFrame
	#tag Note, Name = About
		One image in a GIF: its rectangle on the logical screen, its palette (NColors = 0: use the
		global one), timing, disposal and transparency, and Pixels: Width*Height colour indices in row order.
	#tag EndNote

	#tag Property, Flags = &h0
		Delay As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Disposal As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Height As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Interlaced As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		Left As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		NColors As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Palette As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h0
		Pixels As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h0
		Top As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Transparent As Integer = -1
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
