#tag Class
Protected Class GTTag
	#tag Note, Name = About
		One TIFF tag: id, type, count, and its values in Data (a MemoryBlock set to the file's byte order).
	#tag EndNote

	#tag Method, Flags = &h0
		Function Number(i As Integer) As Double
		  // Value i of any numeric type, as a Double
		  If Data = Nil Or i < 0 Or i >= Count Then Return 0
		  Var p As Integer = i * GTFile.TypeSize(TypeCode)
		  Select Case TypeCode
		  Case TIFF.TIF_BYTE, TIFF.TIF_UNDEFINE, TIFF.TIF_ASCII
		    Return Data.Byte(p)
		  Case TIFF.TIF_SBYTE
		    Return Data.Int8Value(p)
		  Case TIFF.TIF_SHORT
		    Return Data.UInt16Value(p)
		  Case TIFF.TIF_SSHORT
		    Return Data.Int16Value(p)
		  Case TIFF.TIF_LONG
		    Return Data.UInt32Value(p)
		  Case TIFF.TIF_SLONG
		    Return Data.Int32Value(p)
		  Case TIFF.TIF_FLOAT
		    Return Data.SingleValue(p)
		  Case TIFF.TIF_DOUBLE
		    Return Data.DoubleValue(p)
		  Case TIFF.TIF_RATIONAL
		    If Data.UInt32Value(p + 4) = 0 Then Return 0
		    Return Data.UInt32Value(p) / Data.UInt32Value(p + 4)
		  Case TIFF.TIF_SRATIONAL
		    If Data.Int32Value(p + 4) = 0 Then Return 0
		    Return Data.Int32Value(p) / Data.Int32Value(p + 4)
		  End Select
		  Return 0
		End Function
	#tag EndMethod

	#tag Property, Flags = &h0
		Count As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		Data As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h0
		ID As Integer
	#tag EndProperty

	#tag Property, Flags = &h0
		TypeCode As Integer
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
