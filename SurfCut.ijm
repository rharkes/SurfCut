// setup Clij and push image to GPU
run("CLIJ Macro Extensions", "cl_device=");
Ext.CLIJ_clear();
setBatchMode(true);
/////////////////////////////////////////////////////////////////////////
////////=======SurfCut=======////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////
////////Copyright 2019 INRA - CNRS///////////////////////////////////////
/////////////////////////////////////////////////////////////////////////
////////File author(s): Stéphane Verger <stephane.verger@slu.se>/////////
/////////////////////////////////////////////////////////////////////////
////////Distributed under the Cecill-C License///////////////////////////
////////See accompanying file LICENSE.txt or copy at/////////////////////
////////http://www.cecill.info/licences/Licence_CeCILL-C_V1-en.html//////
/////////////////////////////////////////////////////////////////////////
// ----------------------------------------------------------------------
// parameters of processing
TRad = 3;
// ----------------------------------------------------------------------
// more setups
run("Input/Output...", "jpeg=85 gif=-1 file=.csv use_file copy_row save_column save_row");
run("Colors...", "foreground=white background=black selection=yellow");
run("Options...", "iterations=1 count=1 black pad edm=16-bit");
setOption("BlackBackground", true);

run("Set Measurements...", "area perimeter redirect=None decimal=3");

if (isOpen("Log")){

	selectWindow("Log");
	run("Close");
}

if (isOpen("Results")){

		run("Results");
}

roiManager("reset");
// ----------------------------------------------------------------------
// Open a stack 
open();

// ----------------------------------------------------------------------
// get file names and directories 
imgDir = File.directory;
print("[INFO] Input directory: " + imgDir);

imgName = getTitle();
print("[INFO] Input file: " + imgName);

imgPath = imgDir + imgName;
resultDir = imgDir + File.separator + "SurfCutResult";
File.makeDirectory(resultDir);

// ----------------------------------------------------------------------
// get voxel size of input image
print("[INFO] loading calibration and dimensions.");
selectImage(imgName);
getVoxelSize(voxWidth, voxHeight, voxDepth, voxUnit);
getDimensions(width, height, channels, slices, frames);
print("[INFO] Detected voxel size: Width: " + voxWidth 
	+ " Height: " 
	+ voxHeight 
	+ " Depth: " 
	+ voxDepth + " Unit: " 
	+ voxUnit);

// ----------------------------------------------------------------------
// Ask the user about cut depth parameters
print("[INFO] verifying calibration.");
Dialog.create("SurfCut Parameters");
Dialog.addMessage("Please verify image calibration\n Voxel dimensions:");
Dialog.addNumber("Width\t", voxWidth);
Dialog.addNumber("height\t", voxHeight);
Dialog.addNumber("Depth\t", voxDepth);
Dialog.show();

voxWidth = Dialog.getNumber();
voxHeight = Dialog.getNumber();
voxDepth = Dialog.getNumber();

selectImage(imgName);
setVoxelSize(voxWidth, voxHeight, voxDepth, voxUnit);

// ----------------------------------------------------------------------
// get image dimensions
print("[INFO] processing stack.");
selectImage(imgName);
run("Duplicate...", "duplicate");
originalImage = "Original";
rename(originalImage);

// ----------------------------------------------------------------------
// Push image to GPU
Ext.CLIJ_push(imgName);

// Blur the image
blurredImage = "Blurred";
Ext.CLIJ_blur3D(imgName, blurredImage, TRad, TRad, 1);
Ext.CLIJ_pull(blurredImage);

selectImage(blurredImage);
setVoxelSize(voxWidth, voxHeight, voxDepth, voxUnit);

// ----------------------------------------------------------------------
//Calculate the threshold for edge detection (sample borders)
print("[INFO] automatic threshold calculation.");
maxx = newArray(slices);
stdx = newArray(slices);

for(a=1; a<slices+1; a++){	//get Maximum Intensity in every slice - sd intensity
	setSlice(a);
	getRawStatistics(area, mean, min, max, std, histogram);
	maxx[a-1]=max;
	stdx[a-1]=std;	
}
Array.getStatistics(maxx, min, max, mean, stdDev);
maxx_min=min;
Array.getStatistics(stdx, min, max, mean, stdDev);

// ----------------------------------------------------------------------
// create threshold based on automatic threshold calculation
print("[INFO] threshold set to: " + maxx_min);
thresholdedImage = "Threshold";
Ext.CLIJx_threshold(blurredImage, thresholdedImage, maxx_min-min);
Ext.CLIJ_pull(thresholdedImage);
setVoxelSize(voxWidth, voxHeight, voxDepth, voxUnit);
run("Multiply...", "value=255.000 stack");
print("[INFO] thresholding complete.");

// ----------------------------------------------------------------------
print("[INFO] calculating top and bottom slice.");

// calculate the boundaries 

for(a=1; a<slices+1; a++){
	
	setSlice(a);
	setThreshold(1,255);
	run("Create Selection");
	run("Measure");
	run("Select None");
	
}

peri_area = newArray(nResults);

peri_area[0] = 10000;
peri_area[1] = 10000;

TBot = 2;

for(a=2; a < nResults; a++){
	
	peri_area[a] = getResult("Perim.", a) / getResult("Area", a);

	//getResult("Perim.", a);
	//getResult("Area", a);
	
	if( peri_area[a] < ( 0.95 * peri_area[a-1] ) ){
		
		TBot = a;
		
	}else{
		
		if( peri_area[a] < ( 0.95 * peri_area[a-2] )){
			
			TBot = a;
			
		}else{
			
			a=10000;
			
		}
	}
}

TTop = TBot - 1;

print("[INFO] extracting slices Top: " + TTop + " Bottom " + TBot);
close("peri_area");

// ----------------------------------------------------------------------
// fill holes and proceed to edge detection
print("[INFO] processing mask.");
selectImage(thresholdedImage);
run("Fill Holes", "stack");

close(blurredImage);
Ext.CLIJ_clear();

// ----------------------------------------------------------------------
//Edge detect
print("[INFO] calculating surface of object.");
selectImage(thresholdedImage);

for(a = 1; a < slices; a++){
	setSlice(a);
	setThreshold(1, 255);
	run("Create Selection");
	setSlice(a + 1);
	run("Fill", "slice");
	run("Select None");
}

selectImage(thresholdedImage);

// ----------------------------------------------------------------------
//add all regions from the mask to the roi manager 
print("[INFO] adding regions from mask to ROI manager.");

for(a=1; a < slices+1; a++){	
	
	setSlice(a);
	setThreshold(1,255);
	run("Create Selection");
	roiManager("Add");
	roiManager("Select", a-1);
	roiManager("Rename", a);
	
}
run("Select None");

roicount=roiManager("count");

roiManager("Remove Slice Info");



// ----------------------------------------------------------------------
//calculate differences between layers (which outline is added in every layer)
print("[INFO] calculating difference between layers.");

for(a=1; a<roicount;a++){	
	
	roiarray=newArray( a-1 ,a);
	roiManager("Select", roiarray);
	roiManager("XOR");
	roiManager("Add");
	
}

// ----------------------------------------------------------------------
// all these rois could already be created in the first step 
// (when masking the sample volume/thresholding (Set_TS_Sigma.ijm)
// delete first rois > only the differences remain (for slices 2-n)
print("[INFO] rename ROIs.");

roiarray=newArray(roicount-1);

for(a=1; a<roicount;a++){
	
	roiarray[a-1]=a;
	
}
roiManager("Select", roiarray);
roiManager("Delete");

roiManager("Remove Slice Info");

for(a=0; a<roiManager("count");a++){	//Rename
	roiManager("Select", a);
	roiManager("Rename", a+1);
}

// ----------------------------------------------------------------------
// Apply rois to original image: duplicate every new layer 
// (only between ttop and tbot for every layer)
// and add it to a final image (image calculator for max intensities)
print("[INFO] getting and projecting nice slices.");

newImage("Final", "8-bit black", width, height, slices);

for(a=0; a<roiManager("count");a++){
	selectImage(imgName);
	run("Select None");
	run("Duplicate...", "duplicate range="+a+TTop+1+"-"+a+TBot+" title=Stack use");	
	roiManager("Select", a);
	run("Clear Outside", "stack");
	run("Select None");

	imageCalculator("Max create stack", "Final","Stack");
	close("Final");
	rename("Final");
	close("Stack");
}


// ----------------------------------------------------------------------
// save & close
print("[INFO] processing finished, saving");

selectImage("Final");
saveAs("Tiff", resultDir + File.separator + imgName + "_SurfCutProj.tif");
close();

selectImage(originalImage);
run("Z Project...", "projection=[Max Intensity]");
saveAs("Tiff", resultDir + File.separator + imgName + "_OriginalProj.tif");
close();

close(imgName);
close(thresholdedImage);
close(originalImage);


if (isOpen("Results")){

		run("Results");
}

roiManager("reset");

print("[WORKFLOW FINISHED]");
