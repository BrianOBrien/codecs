#tag Module
Protected Module TIFF
	#tag Note, Name = About
		TIFF and GeoTIFF constants, the same names as tiff.h in the C version
		(which keeps the names of Brian O'Brien's tiff.h from 2000).
	#tag EndNote

	#tag Constant, Name = GK_GTCitation, Type = Double, Dynamic = False, Default = \"1026", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GTModelType, Type = Double, Dynamic = False, Default = \"1024", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GTRasterType, Type = Double, Dynamic = False, Default = \"1025", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GeogAngularUnits, Type = Double, Dynamic = False, Default = \"2054", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GeogCitation, Type = Double, Dynamic = False, Default = \"2049", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GeogEllipsoid, Type = Double, Dynamic = False, Default = \"2056", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GeogGeodeticDatum, Type = Double, Dynamic = False, Default = \"2050", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GeogInvFlattening, Type = Double, Dynamic = False, Default = \"2059", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GeogSemiMajorAxis, Type = Double, Dynamic = False, Default = \"2057", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_GeographicType, Type = Double, Dynamic = False, Default = \"2048", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_PCSCitation, Type = Double, Dynamic = False, Default = \"3073", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_ProjCoordTrans, Type = Double, Dynamic = False, Default = \"3075", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_ProjLinearUnits, Type = Double, Dynamic = False, Default = \"3076", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_ProjectedCSType, Type = Double, Dynamic = False, Default = \"3072", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_Projection, Type = Double, Dynamic = False, Default = \"3074", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_VerticalCSType, Type = Double, Dynamic = False, Default = \"4096", Scope = Public
	#tag EndConstant

	#tag Constant, Name = GK_VerticalUnits, Type = Double, Dynamic = False, Default = \"4099", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_ARTIST, Type = Double, Dynamic = False, Default = \"315", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_ASCII, Type = Double, Dynamic = False, Default = \"2", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_BITSPERSAMPLE, Type = Double, Dynamic = False, Default = \"258", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_BYTE, Type = Double, Dynamic = False, Default = \"1", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COLORMAP, Type = Double, Dynamic = False, Default = \"320", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMPRESSION, Type = Double, Dynamic = False, Default = \"259", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_CCITT, Type = Double, Dynamic = False, Default = \"2", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_DEFLATE, Type = Double, Dynamic = False, Default = \"8", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_DEFLATE_OLD, Type = Double, Dynamic = False, Default = \"32946", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_JPEG, Type = Double, Dynamic = False, Default = \"7", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_LZW, Type = Double, Dynamic = False, Default = \"5", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_NONE, Type = Double, Dynamic = False, Default = \"1", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_OJPEG, Type = Double, Dynamic = False, Default = \"6", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_COMP_PACKBITS, Type = Double, Dynamic = False, Default = \"32773", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_DATETIME, Type = Double, Dynamic = False, Default = \"306", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_DOUBLE, Type = Double, Dynamic = False, Default = \"12", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_EXTRASAMPLES, Type = Double, Dynamic = False, Default = \"338", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_FLOAT, Type = Double, Dynamic = False, Default = \"11", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_GDAL_METADATA, Type = Double, Dynamic = False, Default = \"42112", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_GDAL_NODATA, Type = Double, Dynamic = False, Default = \"42113", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_GEOASCIIPARAMS, Type = Double, Dynamic = False, Default = \"34737", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_GEODOUBLEPARAMS, Type = Double, Dynamic = False, Default = \"34736", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_GEOKEYDIRECTORY, Type = Double, Dynamic = False, Default = \"34735", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_HOSTCOMPUTER, Type = Double, Dynamic = False, Default = \"316", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_IMAGEDESCRIPTION, Type = Double, Dynamic = False, Default = \"270", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_IMAGELENGTH, Type = Double, Dynamic = False, Default = \"257", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_IMAGEWIDTH, Type = Double, Dynamic = False, Default = \"256", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_INTEL, Type = Double, Dynamic = False, Default = \"18761", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_LONG, Type = Double, Dynamic = False, Default = \"4", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_MODELPIXELSCALE, Type = Double, Dynamic = False, Default = \"33550", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_MODELTIEPOINT, Type = Double, Dynamic = False, Default = \"33922", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_MODELTRANSFORMATION, Type = Double, Dynamic = False, Default = \"34264", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_MOTOROLA, Type = Double, Dynamic = False, Default = \"19789", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_NEWSUBFILE, Type = Double, Dynamic = False, Default = \"254", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_ORIENTATION, Type = Double, Dynamic = False, Default = \"274", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_PHOTOMETRICINTERPRETAION, Type = Double, Dynamic = False, Default = \"262", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_PLANARCONFIGURATION, Type = Double, Dynamic = False, Default = \"284", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_PREDICTOR, Type = Double, Dynamic = False, Default = \"317", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_PRED_FLOAT, Type = Double, Dynamic = False, Default = \"3", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_PRED_HORIZONTAL, Type = Double, Dynamic = False, Default = \"2", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_PRED_NONE, Type = Double, Dynamic = False, Default = \"1", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_RATIONAL, Type = Double, Dynamic = False, Default = \"5", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_RESOLUTIONUNIT, Type = Double, Dynamic = False, Default = \"296", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_ROWSPERSTRIP, Type = Double, Dynamic = False, Default = \"278", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SAMPLEFORMAT, Type = Double, Dynamic = False, Default = \"339", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SAMPLESPERPIXEL, Type = Double, Dynamic = False, Default = \"277", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SBYTE, Type = Double, Dynamic = False, Default = \"6", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SHORT, Type = Double, Dynamic = False, Default = \"3", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SLONG, Type = Double, Dynamic = False, Default = \"9", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SOFTWARE, Type = Double, Dynamic = False, Default = \"305", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SRATIONAL, Type = Double, Dynamic = False, Default = \"10", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_SSHORT, Type = Double, Dynamic = False, Default = \"8", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_STRIPBYTECOUNTS, Type = Double, Dynamic = False, Default = \"279", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_STRIPOFFSETS, Type = Double, Dynamic = False, Default = \"273", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_TILEBYTECOUNTS, Type = Double, Dynamic = False, Default = \"325", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_TILELENGTH, Type = Double, Dynamic = False, Default = \"323", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_TILEOFFSETS, Type = Double, Dynamic = False, Default = \"324", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_TILEWIDTH, Type = Double, Dynamic = False, Default = \"322", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_UNDEFINE, Type = Double, Dynamic = False, Default = \"7", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_VERSION, Type = Double, Dynamic = False, Default = \"42", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_XRESOLUTION, Type = Double, Dynamic = False, Default = \"282", Scope = Public
	#tag EndConstant

	#tag Constant, Name = TIF_YRESOLUTION, Type = Double, Dynamic = False, Default = \"283", Scope = Public
	#tag EndConstant


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
