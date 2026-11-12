#tag Class
Protected Class GTWriteOptions
	#tag Note, Name = About
		How GTWriter.Write should write a GeoTIFF. GT() is GDAL's order, corner-based:
		X = GT(0) + GT(1)*col + GT(2)*row, Y = GT(3) + GT(4)*col + GT(5)*row.
	#tag EndNote

	#tag Property, Flags = &h0
		Citation As String
	#tag EndProperty

	#tag Property, Flags = &h0
		Compression As Integer = 5
	#tag EndProperty

	#tag Property, Flags = &h0
		EPSG As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Geographic As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		GT(5) As Double
	#tag EndProperty

	#tag Property, Flags = &h0
		HasTransform As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		PixelIsPoint As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		Predictor As Integer = 1
	#tag EndProperty

	#tag Property, Flags = &h0
		RowsPerStrip As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		SampleFormat As Integer = 1
	#tag EndProperty

	#tag Property, Flags = &h0
		Software As String
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
