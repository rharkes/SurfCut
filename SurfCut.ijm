// setup Clij and push image to GPU
run("CLIJ Macro Extensions", "cl_device=");
Ext.CLIJ_clear();
setBatchMode(false);
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

///=================================///
///==========SurfCut Macro==========///
///=================================///

// parameters of processing ---------------------------------------------
TRad = 3;

///Open a stack for calibration ---------------------------------------------
open();
imgDir = File.directory;
print(imgDir);
imgName = getTitle();
print(imgName);
imgPath = imgDir+imgName;
print(imgPath);

File.makeDirectory(imgDir+File.separator+"SurfCutCalibrate");

selectImage(imgName);
run("Duplicate...", "duplicate");
originalImage = "Original";
rename(originalImage);

// get voxel size of input image ---------------------------------------------
selectImage(originalImage);
getVoxelSize(width, height, depth, unit);
print(width + " " + height + " " + depth);
print("Detected voxel size:\nWidth --> " + width + "\nHeight --> " + height + "\nDepth --> " + depth + "\nUnit --> " + unit);

// get image dimensions ---------------------------------------------
getDimensions(width, height, channels, slices, frames);
run("Set Measurements...", "area perimeter redirect=None decimal=3");


// Push image to GPU
Ext.CLIJ_push(imgName);

// Blur the image
blurredImage = "Blurred";
Ext.CLIJ_blur3D(imgName, blurredImage, TRad, TRad, 1);
Ext.CLIJ_pull(blurredImage);

selectImage(blurredImage);
setVoxelSize(width, height, depth, unit);

//Calculate the threshold for edge detection (sample borders)
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

// create threshold based on automatic threshold calculation
thresholdedImage = "Threshold";
Ext.CLIJx_threshold(blurredImage, thresholdedImage, maxx_min-min);
Ext.CLIJ_pull(thresholdedImage);
setVoxelSize(width, height, depth, unit);
run("Multiply...", "value=255.000 stack");

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

Array.show(peri_area);

for(a=2; a < nResults; a++){
	
	peri_area[a] = getResult("Perim.", a) / getResult("Area", a);

	getResult("Perim.", a);
	getResult("Area", a);
	Array.show(peri_area);
	
	if( peri_area[a] < ( 0.95 * peri_area[a-1] ) ){
		
		TBot=a;
		
	}else{
		
		if( peri_area[a] < ( 0.95 * peri_area[a-2] )){
			
			TBot=a;
			
		}else{
			
			a=10000;
			
		}
	}
}

TTop = TBot - 1;

print("Top: " + TTop + " TBot " + TBot);

// fill holes and proceed to edge detection
selectImage(thresholdedImage);
run("Fill Holes", "stack");

close(blurredImage);
Ext.CLIJ_clear();

//Edge detect
selectImage(thresholdedImage);

for(a = 1; a < slices; a++){
	setSlice(a);
	setThreshold(1, 255);
	run("Create Selection");
	setSlice(a + 1);
	run("Fill", "slice");
	run("Select None");
}

RdWth = round(width*1000)/1000;
RdHgt = round(height*1000)/1000;
RdDpt = round(depth*1000)/1000;

// Ask the user about cut depth parameters
Dialog.create("SurfCut Parameters");
Dialog.addMessage("4) Voxel properties in micrometers\nare automatically retrieved from the\nimage metadata.\n!!!\nIf no value was available they are all\nset to 1.\nUse rounded values (for example\n0.500 instead of 0.501...) and with\na maximum 3 decimals");
Dialog.addNumber("Width\t", RdWth);
Dialog.addNumber("height\t", RdHgt);
Dialog.addNumber("Depth\t", RdDpt);
Dialog.show();

Wth = Dialog.getNumber();
Hgt = Dialog.getNumber();
Dpt = Dialog.getNumber();

selectImage(thresholdedImage);

//getDimensions(width, height, channels, slices, frames);
//add all regions from the mask to the roi manager 
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

for(a=1; a<roicount;a++){	//calculate differences between layers (which outline is added in every layer)
	
	roiarray=newArray( a-1 ,a);
	roiManager("Select", roiarray);
	roiManager("XOR");
	roiManager("Add");
	
}
//all these rois could already be created in the first step (when masking the sample volume/thresholding (Set_TS_Sigma.ijm)
//delete first rois > only the differences remain (for slices 2-n)
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

//Apply rois to original image: duplicate every new layer (only between ttop and tbot for every layer)
//and add it to a final image (image calculator for max intensities)

newImage("Final", "8-bit black", width, height, depth);

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
