function img = serConvert(varargin)
% Open *.ser files and save to image. 
% Options is a cell array. Implemented so far:
% - 'fname': path to image. default: none/launch GUI.
% - 'scalebar': 'on'/'off' burns a scalebar into the image. default: on
% - 'format': 'png'/'jpg'/'tiff' file formats. default: png
% - 'power': the image is raised to this power (sets gamma, sorta?).
%           default: 0.5
% - 'scaleColor': intensity in [0 1] for scalebar. default: white or black depending
%           on image values in scalebar region
% - 'show': 'on'/'off' display the final image. default: 'off'
% - 'save': true/false save image in specified format automatically.
%           default: true

% parse inputs:
defaultScaleBar = 'on';
defaultFormat = 'png';
defaultPower = 0.5;
defaultfName = '';

p = inputParser;
addParameter(p,'scalebar',defaultScaleBar);
addParameter(p,'format',defaultFormat);
addParameter(p,'power',defaultPower);
addParameter(p,'fname',defaultfName);
addParameter(p,'scaleColor',[]);
addParameter(p,'show',false);
addParameter(p,'save',true);

parse(p,varargin{:});

options = p.Results;

% load ser file and get data
if isempty(options.fname)
    ser = serReader();
else
    ser = serReader(options.fname);
end

filename = ser.filename;

% scale the gamma/power of the image
if min(ser.image(:)) < 0
    ser.image = ser.image - min(ser.image(:));
end
img = (ser.image.^options.power);
pixsz = ser.pixelSizeY; %only use x scale. if they're different, good luck
%flip image around
img = rot90(img);
imSize = size(img);

% normalize the image to [0 1]
img = img ./ max(img(:));

% draw scalebar if requested
if options.scalebar
    
    scales = [ 0.1 0.2 0.5 1 5 10 20 50 100 200 500 1000 2000 5000] * 1e-9; %nm
    
    approxLength = 0.125 * imSize(2) * pixsz; % rough real length of scalebar
    
    % get the scalebar length that's closest to the target proportions
    [~,ind] = min(abs(scales - approxLength));
    scalebarRealLength = scales(ind);
    
    scaleBarPixels = scalebarRealLength / pixsz;
    
    
    if isempty(options.scaleColor)
        %get average img value in the scalebar corner and set color as
        %appropriate
        avgImgValue = img( floor(0.8*imSize(1)):end,1:floor(0.25*imSize(2)));
        avgImgValue = mean(avgImgValue(:));
        if avgImgValue > 0.3
            scaleColor = 0;
        else
            scaleColor = 1;
        end
    else
        scaleColor = options.scaleColor;
    end
    
    % get the scalebar position
    insetX = floor(0.9*imSize(1));
    insetY = floor(0.06*imSize(2));
    height = floor(0.01 * imSize(1));
    
    % this needs a toolbox, which is annoying :(
    img = insertShape(img, 'FilledRectangle', [ insetY insetX scaleBarPixels height ], ...
        'color', [scaleColor scaleColor scaleColor],'Opacity',1);
    
    %ghetto way to draw scalebar
    %img(insetX:insetX+height, insetY:insetY+scaleBarPixels) = scaleColor;
    
    % insert scalebar text
    img = insertText(img, [floor(insetY+(scaleBarPixels)/2) insetX+floor(0.01*imSize(1))],...
        [num2str(scalebarRealLength*1e9) ' nm'], 'FontSize',round(160*imSize(1)/4000),...
        'TextColor',[scaleColor scaleColor scaleColor],'BoxOpacity',0,...
        'AnchorPoint','CenterTop');
    
end

if options.show
    imagesc(img);
    axis image off;
end

if options.save
    imwrite(img,[filename(1:end-3) options.format],options.format);
end

end

%%%%%%%%%%%%%%%%% SER READER (PETER ERCIUS) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%serReader() function
%	Description:
%		File reader for .ser files from FEI's TIA or Emispec acquisition programs for electron microscopes. Reads in data from .SER files and the data is divided into "elements" such as line scans, spectra or images
%	Parameters:
%		fname - the filename of the SER file to be read. If not provided the program opens a dialog box to choose a file
%	Limitations:
%		Complex datatypes are currenty unsupported and will cause the program to fail
%	Output:
% 		Ser - a matlab structure that contains the data and the pixel sizes for each data element
%	Author:
%		Peter Ercius 2009/08/06
function Ser = serReader(fName)

	fPath = '';
    
    cellFlag = 0;
    
    if nargin == 0
        [fName, fPath] = uigetfile('*.ser');
    end
	
	if fName == 0
		error('No file opened.');
	end
	
    [FID, FIDmessage] = fopen([fPath fName],'rb');
    if FID == -1
		disp(fName)
		error(['Issue opening file: ' FIDmessage])
    end

	%Read in the header information
	byteOrder = fread(FID,1,'int16'); %dec2hex(byteOrder) should be 4949
	seriesID = fread(FID,1,'int16'); %value 0x0197 indicates ES Vision Series Data File
	seriesVersion = fread(FID,1,'int16');
	dataTypeID = fread(FID,1,'int32'); %0x4120 = 1D arrays; 0x4122 = 2D arrays
	tagTypeID = fread(FID,1,'int32'); %0x4152 = Tag is time only; 0x4142 = Tag is 2D with time
    
    if seriesVersion <= 528 %This might need to be reduced. TIA 4.7.3 uses this series version and requires the newer dataOffsetArray reading process (int64) 
        offsetArrayType = 'int32'; %used for older versions of TIA before TIA 4.7.3 (Titan 1.6.4)
    else
        offsetArrayType = 'int64'; %#used for newer versions of TIA after TIA 4.7.3 (Titan 1.6.4) (not sure of this exact version number)
    end

	totalNumberElements = fread(FID,1,'int32'); %the number of data elements in the original data set
	validNumberElements = fread(FID,1,'int32'); %the number of data elements written to the file
	offsetArrayOffset = fread(FID,1,'int32'); %the offset (in bytes) to the beginning of the data offset array
	
	numberDimensions = fread(FID,1,'int32'); %the number of dimensions of the indices (not the data)
	
	%%
	%Dimension arrays (starts at byte offset 30)
    description = '';
    units = '';
    dimensionSize = 1;
    for ij = 1:numberDimensions
        dimensionSize(ij) = fread(FID,1,'int32'); %the number of elements in this dimension
        calibrationOffset(ij) = fread(FID,1,'float64'); %calibration value at element calibrationElement
        calibrationDelta(ij) = fread(FID,1,'float64'); %calibration delta between elements of the series
        calibrationElement(ij) = fread(FID,1,'int32'); %the element in the series with a calibraion value of calibrationOffset
        descriptionLength(ij) = fread(FID,1,'int32'); %length of the description string
        description{ij} = fread(FID,descriptionLength(ij),'*char')'; %describes the dimension
        unitsLength(ij) = fread(FID,1,'int32'); %length of the units string
        units{ij} = fread(FID,unitsLength(ij),'*char')'; %name of the units in this dimension
    end
    
	%%
	%Get arrays containing byte offsets for data and tags
    fseek(FID,offsetArrayOffset,-1); %seek in the file to the offset arrays
	%Data offset array (the byte offsets of the individual data elements)
	dataOffsetArray = fread(FID,totalNumberElements,offsetArrayType);
	%Tag Offset Array (byte offsets of the individual data tags)
	tagOffsetArray = fread(FID,totalNumberElements,offsetArrayType);
	
	%%
	%Get data from 1D elements
    if dataTypeID == hex2dec('4120')
        arrayLength = zeros(validNumberElements); %pre-allocate
        
        for ii=1:validNumberElements
            fseek(FID,dataOffsetArray(ii),-1);
			calibrationOffset = fread(FID,1,'float64'); %calibration value at element calibrationElement
			calibrationDelta = fread(FID,1,'float64'); %calibration delta between elements of the array
			calibrationElement = fread(FID,1,'int32'); %element in the array with calibration value of calibrationOffset
			dataType = fread(FID,1,'int16'); %
            
			Type = getType(dataType);
			arrayLength(ii) = fread(FID,1,'int32'); %number of elements in the array
            
            %Set up test to convert cell to matrix later if all arrays are
            %the same size
            if ii == 1
                arrayLength0 = arrayLength(1);
                cellFlag = 1;
            elseif arrayLength0 ~= arrayLength(ii)
                cellFlag = 0;
            end

			Ser.data{ii} = fread(FID,arrayLength(ii),Type);
			energy = linspace(calibrationOffset,calibrationOffset+(arrayLength(ii)-1)*calibrationDelta,arrayLength(ii));
			Ser.calibration{ii} = energy;
        end
        
        %Save and pre-calculate some useful image things
        Ser.dispersion = calibrationDelta;
        Ser.energyOffset = calibrationOffset;
        Ser.filename = fName;
        
        %If possible, change cell array to matrix
        if cellFlag
            if length(dimensionSize) == 1
                Ser.spectra = reshape(cell2mat(Ser.data)',validNumberElements,arrayLength0);
                Ser.calibration = energy;
            elseif length(dimensionSize) == 2
                Ser.SI = reshape(cell2mat(Ser.data)',dimensionSize(1),dimensionSize(2),arrayLength0);
                Ser.calibration = energy;
            end
            Ser = rmfield(Ser,'data'); %remove the data cell from the struct
        end
        
    %Get data from 2D elements
    elseif dataTypeID == hex2dec('4122')
		Ser.calibration = zeros(2, validNumberElements);
        for ii=1:validNumberElements
			fseek(FID,dataOffsetArray(ii),-1);
			calibrationOffsetX = fread(FID,1,'float64'); %calibration at element calibrationElement along x
			calibrationDeltaX = fread(FID,1,'float64');
			calibrationElementX = fread(FID,1,'int32'); %element in the array along x with calibration value of calibrationOffset
			calibrationOffsetY = fread(FID,1,'float64');
			calibrationDeltaY = fread(FID,1,'float64');
			calibrationElementY = fread(FID,1,'int32');
			dataType = fread(FID,1,'int16');
            
			Type = getType(dataType);
			arraySizeX = fread(FID,1,'int32');
			arraySizeY = fread(FID,1,'int32');
            
			Ser.data{ii} = fread(FID,[arraySizeX arraySizeY],Type);
			Ser.calibration(:,ii) = [calibrationDeltaX calibrationDeltaY]';
        end
		
        if validNumberElements == 0
			Ser.image = []; %return empty matrix
			Ser.calibration = []; %return empty matrix
        else
            %Save and pre-calculate some useful image things
            Ser.pixelSizeX = calibrationDeltaX;
            Ser.pixelSizeY = calibrationDeltaY;
            Ser.xAxis = linspace(calibrationOffsetX,-calibrationOffsetX,arraySizeX);
            Ser.yAxis = linspace(calibrationOffsetY,-calibrationOffsetY,arraySizeY);
            Ser.filename = fName;
        end
        
		%Check to see if only one object was valid
		%Remove cell 
        if validNumberElements == 1
			Ser.image = Ser.data{1};
			Ser = rmfield(Ser,'data');
        end


    end
	%%
	%Read in the tags
	%Get data from "Time-only" tags
	if tagTypeID == hex2dec('4152')
		for jj=1:validNumberElements
			fseek(FID,tagOffsetArray(jj),-1);
			tagTypeID2 = fread(FID,1,'int16'); %type of the tag (should be 0x4152 or 16722)
			Ser.timeTag(jj) = fread(FID,1,'int32'); %number of seconds since Jan. 1, 1970
	end
	%Get data from Time-and-Position tags
	elseif tagTypeID == hex2dec('4142')
        newTags = zeros(3,validNumberElements);
		for jj=1:validNumberElements
			fseek(FID,tagOffsetArray(jj),-1);
			tagTypeID2 = fread(FID,1,'int16');
			Ser.scanTags(1,jj) = fread(FID,1,'uint32'); %time Tag
            Ser.scanTags(2,jj) = fread(FID,1,'float32'); %xTag
            Ser.scanTags(3,jj) = fread(FID,1,'float32'); %yTag
            %timeTag = fread(FID,1,'int32');
			%xTag = fread(FID,1,'float');
			%yTag = fread(FID,1,'float');
            %disp(tagTypeID2)
            %disp([num2str(xTag) ' ' num2str(yTag)]);
        end
        if length(dimensionSize) == 2
            Ser.scanTags = reshape(Ser.scanTags',dimensionSize(1),dimensionSize(2),3);
        end
	else disp(['Unknown time tag type ' num2str(tagTypeID) ' in ' fName])	
	end

	%%
	%Clean up and write out the data
	disp(['Total elements read: ' num2str(validNumberElements)])
	fclose(FID);
    
end

function Type = getType(dataType)
    Type = 0;
    switch dataType
		case 1
			Type = 'uint8';
		case 2
			Type = 'uint16';
		case 3
			Type = 'uint32';
		case 4
			Type = 'int8';
		case 5
			Type = 'int16';
		case 6
			Type = 'int32';
		case 7
			Type = 'float32';
		case 8
			Type = 'float64';
        case 12
            Type = 'int32';
		otherwise
			error('Unsupported data type') %complex data types are unsupported currently
    end
end