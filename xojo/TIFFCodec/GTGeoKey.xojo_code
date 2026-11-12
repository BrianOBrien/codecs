#tag Class
Protected Class GTGeoKey
	#tag Note, Name = About
		One GeoKey from the GeoKeyDirectory tag. Location 0: the value is ValueOrIndex;
		otherwise the tag (GeoDoubleParams or GeoAsciiParams) holding it, at index ValueOrIndex.
	#tag EndNote

	#tag Property, Flags = &h0
		Count As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		ID As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Location As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		ValueOrIndex As Integer
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
