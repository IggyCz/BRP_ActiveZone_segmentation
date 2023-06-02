run("Set Measurements...", "area mean standard min integrated display redirect=None decimal=3");

//global name variable for storing filenames
var name;

input = getDirectory("input folder");
output = getDirectory("output folder");

Dialog.create("Settings");
Dialog.addCheckbox("New ROI", 1);
Dialog.addSlider("BRP Threshold", 0, 65535, 1000);
Dialog.show();
newROI = Dialog.getCheckbox();
lower = Dialog.getNumber();

//Makes result file (.csv)
var resultFileLine;
resultFileLineMod("init", "File", true);
resultFileLineMod("append", "Mean", true);
resultFileLineMod("append", "Area", true);
resultFileLineMod("append", "RawIntensity", true);
resultFileLineMod("append", "Max", true);
resultFileLineMod("append", "Count", false);
resultFileLineMod("writeFile", output + "\\results.csv", false);

//Gets list of files in selected input directory
list = getFileList(input);

//sets BatchMode, i.e. prevents windows from appearing
//does not work for current macro (?)
setBatchMode(false); 

//iterates through each file in directory
for (i = 0; i < list.length; i++){
		//runs bioformats function on individual files
        bio_formats_open(input, list[i]);
}

//function which opens files and iterates through all sub-files (e.g. in .lif format) opening one at a time
//and running the functions defined in "main()"
function bio_formats_open(in_dir, filename){
	run("Bio-Formats Macro Extensions");
	seriesToOpen = newArray;
	sIdx = 0;
	path = in_dir+filename;
	print(path);
	Ext.setId(path);
	Ext.getSeriesCount(seriesCount);
	//iterates through all sub-files in file (e.g. in .lif format) superfluous for files such as .tif but should work regardless
	for(s = 1; s <= seriesCount; s++){
	run("Bio-Formats Importer", "open=[" + path + "] autoscale color_mode=Composite rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT series_"+s+"");
	//runs main function
	roiManager("reset");
	run("Clear Results");
	name = getTitle();
	resultFileLineMod("init", name, true);
	main();	
	resultFileLineMod("writeFile", output + "\\results.csv", false);
	//closes all windows to repeat loop
	run("Close All");
	}
}


function main(){
	original = getImageID();
	run("Duplicate...", "duplicate channels=1");
	run("Z Project...", "projection=[Sum Slices]");
	BRP_sum = getImageID();
	
	selectImage(original);
	run("Duplicate...", "duplicate channels=2");
	run("Z Project...", "projection=[Max Intensity]");
	membraneProjection = getImageID();
	selectImage(original);
	run("Duplicate...", "duplicate channels=1");
	run("Z Project...", "projection=[Max Intensity]");
	BRPMax = getImageID();
	//conditional to either make new ROI and clear background
	//or use existing and clear background
	if (newROI == true){
		membraneProjection = selectROI(membraneProjection);
	}
	else {
		open(output + "\\" + name + "_mask.tif");
		//run("Invert");
		run("Create Selection");
		roiManager("add");
		selectImage(membraneProjection);
		roiManager("select", 0);
		run("Clear Outside");
		roiManager("reset");
	}
	selectImage(membraneProjection);
	setAutoThreshold("Li dark");
	//run("Threshold...");
	run("Convert to Mask");
	run("Erode");
	run("Dilate");
	run("Fill Holes");
	run("Analyze Particles...", "size=100-Infinity pixel circularity=0.0-0.50 exclude include add");
	//waitForUser("Debug");
	if (roiManager("count") > 0){
	membraneMask = mergeROI();
	selectImage(BRP_sum);
	roiManager("measure");
	mergeResults();
	run("Clear Results");
	brpMask = brpPuncta(BRPMax);
	selectImage(original);
	run("Z Project...", "projection=[Max Intensity]");
	originalProjection = getImageID();
	overlay = make_overlay(originalProjection, membraneMask, "cyan");
	overlay = make_overlay(overlay, brpMask, "yellow");
	saveAs("Tiff", output + "\\" + getTitle()+"_overlay");
	//waitForUser("Debug");
	}
}

//Pauses macro for user to select a region of interest
//takes an image ID and returns the image with the region outside
//the selcetion removed
function selectROI(inputImage){
	selectImage(inputImage);
	setBatchMode(false);
	waitForUser("Select region of interest");
	roiManager("add");
	roiManager("select", 0);
	run("Clear Outside");
	run("Create Mask");
	saveAs("Tiff", output + "\\" + name +"_mask");
	roiManager("reset");
	resetMinAndMax();
	//setBatchMode(true);
	selectImage(inputImage);
	return getImageID();
}

//function which takes the the BRP channel and requires existing selection
// of ROIs of membrane creates a results window with the count of points
//and a point selection for merge with overlay

function brpPuncta(brpRaw){
	roiManager("deselect");
	selectImage(brpRaw);
	run("Duplicate...", " ");
	brpMask = getImageID();
	mergeROI();
	roiManager("select", 0);
	run("Clear Outside");
	//run("Enhance Contrast...", "saturated=0.35 normalize equalize");
	//run("8-bit");
	roiManager("deselect");
	roiManager("reset");
	setThreshold(lower, 65535, "raw");
	setOption("BlackBackground", true);
	//setAutoThreshold("Otsu dark");
	run("Convert to Mask");
	run("Analyze Particles...", "size=4-Infinity pixel circularity=0.0-1.0 exclude include add");
	mergeROI();
	selectImage(brpRaw);
	roiManager("select", 0);
	run("Clear Outside");
	run("Find Maxima...", "prominence=1000 strict exclude output=Count");
	count = getResult("Count", 0);
	resultFileLineMod("append", count, false);
	run("Find Maxima...", "prominence=1000 strict exclude output=[Single Points]");
	return getImageID();
	//run("Find Maxima...", "prominence=1000 strict exclude output=[Point Selection]");
}

//returns array of indexes in ROI manager
function mergeROI(){
	roiManager("deselect");
	roiManager("combine");
	run("Create Mask");
	mask = getImageID();
	run("Create Selection");
	roiManager("reset");
	roiManager("add");
	run("Close");
	return getImageID();
}


//takes multiple result rows and merges them so that total mean
//takes no input and works with current results, remember to reset
function mergeResults(){
	intensity = 0;
	area = 0;
	max = 0;
	for (i = 0; i < roiManager("count"); i++){
			intensity = intensity + getResult("IntDen", i);
	}
	for (i = 0; i < roiManager("count"); i++){
			area = area + getResult("Area", i);
	}
	for (i = 0; i < roiManager("count"); i++){
		if(getResult("Max", i) > max){
			max = getResult("Max", i);
		}
	}
	mean = intensity/area;
	resultFileLineMod("append", mean, true);
	resultFileLineMod("append", area, true);
	resultFileLineMod("append", intensity, true);
	resultFileLineMod("append", max, true);
}


//function to saves images (in this context overlay of ROI)
function make_overlay(image, binary, colour){
	n_1 = roiManager("count");
	selectImage(binary);
	run("Create Selection");
	roiManager("add");
	selectImage(image);
	roiManager("select", n_1);
	//setColor(colour);
	Overlay.addSelection(colour);
	return image
}

//Takes key word to either make a new file (init)
// add an entry, or write the file.
//start a new line by addSeparator = false
//parameter is variable to be written
function resultFileLineMod(command, parameter, addSeparator){
	resultFileSeparator=", ";
	if (command=="init")	{
		resultFileLine=""+parameter;	
		if (addSeparator)	{
			resultFileLine=resultFileLine+""+resultFileSeparator;	}	}
	else if (command=="append")	{
		resultFileLine=resultFileLine+""+parameter;
		if (addSeparator)	{
			resultFileLine=resultFileLine+""+resultFileSeparator;	}	}
	else if (command=="writeFile")	{
		File.append(resultFileLine, parameter);	}
}
