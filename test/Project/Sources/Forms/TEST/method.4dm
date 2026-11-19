Case of 
	: (Form event:C388=On Load:K2:1)
		
		ARRAY PICTURE:C279(Column1;0)
		C_LONGINT:C283(Capture)
		
		$device:=CAPTURE DEVICE Get default 
		Capture:=CAPTURE PREVIEW Create ($device)
		
		If (Capture#0)
			OBJECT SET ENABLED:C1123(*;"Stop";False:C215)
			OBJECT SET ENABLED:C1123(*;"Snap";False:C215)
			CAPTURE PREVIEW SET WINDOW (Capture;Current form window:C827)
			OBJECT GET COORDINATES:C663(*;"PreviewArea";$left;$top;$right;$bottom)
			$width:=$right-$left
			$height:=$bottom-$top
			CAPTURE PREVIEW SET RECT (Capture;$left;$top;$width;$height)
		End if 
		
	: (Form event:C388=On Unload:K2:2)
		
		If (Capture#0)
			CAPTURE PREVIEW CLEAR (Capture)
		End if 
		CLEAR VARIABLE:C89(Column1)
End case 