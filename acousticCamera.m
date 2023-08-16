% @title        Acoustic Camera
% @file         acousticCamera.m
% @short        a delay and sum algorithm for the acoustic image extraction
% @version      0.1
% @date         06. September 2021
% @copyright    All rights reserved by Christoph Lauer
% @author       Christoph Lauer
% @contributors persons
% @client       company
% @language     MATLAB R2021a (Octave) 
% @packages     none
% @param        none
% @return       none
% @notes        replace PARFOR with FOR if you have no Parallel Processing
% Toolbox       Image Processing Toolbox, Parallel Computing Toolbox...
% @todo         finished so far
% @copyright    Christoph Lauer
% @license      GPL 3.0
% @brief        This matlab file implements an Delay and Sum algorithm and generates images and a video
% @contact      christophlauer@me.com
% @webpage      https://christoph-lauer.github.io
%
% The matlab script is splitted in 5 parts. The main concepts used in the raytracing beamformer is the  virtual-
% projection-pane and the delay and sum algorithm which will be described here in more detail. In front of the microphone
% array a rectangle is projected with distance z. The rectangle has the width x and the height y. The main concept behind
% the delay and sum algorithm is the distance of the single microphones and the discrete points of the virtual-projection-
% plane. The projection plane is divided into discrete points with the dimension delta. The distance between the single
% microphones and the points in the virtual-projection-plane can be expressed in value with the unit meter and also
% expressed in a value with the unit samples. The disatnce in METER can be converted in SAMPLES trough the speed of sound.
% This means that the distance can be expressed as INDEX POINTER in the samples vector which allows a fast implementation
% in c-similar languages via pointers. The delay values of the microphone array can so be shifted over the virtual-
% projection-plane and single image points can be sampled as ray between the SUM of all (time DELAY shifted) microphones
% of the microphone-array. This algorithm is well known as the DELAY and SUM Algorithm (Δ-Σ). The algorithm can be found
% in section 3 of the source code in this script. Another concept used in the script is windowing. The time aligned sample
% vector is splitted into intervals of the window-length (no overlapping) and ONE image is generated for each time-window.
% The virtual-projection-plane is placed symetrical arround the X and Y axis in this implementation and cannot bet shifted
% up/down left or right. At the end of the script an movie is generated from the image sequence. To disable the
% parallelization replace the PARFOR command in the image main loop with FOR.


%% 0.) CONSTANTS
% NOTE: some constants are defined while read the metadata
clear;
temperature   = 20.0;                    % ϑ in °C
speedOfSound = (331.5 + 0.6*temperature);% v in meter/second
projectionPlaneDistance = 3;             % Z in meter
projectionPlaneWidth    = 4;             % X in meter
projectionPlaneHeight   = 4;             % Y in meter
projectionPlaneDelta    = 0.05;          % Δ in meter (influences the image size)
samplesPerImage         = 1000;          % N in samples (aka window size, no overlapping)


%% 1.) RAW DATA AND METADATA
% parse the microphone array raw data
% 1.1) open the array metadata JSON file and extract the microphone array recording metadata
fid = fopen('data/MicrophoneArrayData.json');
str = char(fread(fid,inf)');
fclose(fid);
metaData = jsondecode(str);
sampleRate = metaData.samplerate;        % f in 1/second CONSTANTS ↑↑↑
numChannels = length(metaData.elements); % C in channels CONSTANTS ↑↑↑
% 1.2) open the RAW audio data
fid = fopen('data/MicrophoneArrayData.raw','rb');
data=fread(fid,[numChannels sampleRate*numChannels],'int16');
fclose (fid);
% 1.3) build the microphone array struct
for m = 1:numChannels
    mic(m).x = metaData.elements(m).x;
    mic(m).y = metaData.elements(m).y;
    mic(m).z = metaData.elements(m).z;
    mic(m).samples = data(m,:);
end
numSamples = length(mic(1).samples);     % n in samples  CONSTANTS ↑↑↑
audiowrite("data/sample.wav",data(100,:)/10000.0,sampleRate) % save one test channel to the disk


%% 2.) PLOT THE ARRAY GEOMETRY AND CALCULATE ETA
% 2.1) plot the geometry of the microphone array
for m = 1:numChannels
    plotX(m) = mic(m).x;
    plotY(m) = mic(m).y;
end
scatter(plotX, plotY)
title('Microphone Array Geometry (in meter)')
% 2.2) calculate the computation times for the APPLE M1 computer
timeImage = numSamples * projectionPlaneWidth/projectionPlaneDelta * projectionPlaneHeight/projectionPlaneDelta / 3e6;
s = seconds(timeImage); s.Format = 'hh:mm:ss';
fprintf("Estimated Computation Duration for ONE image :" + char(s) + " (hh:mm:ss) without Parallelization\n");
timeVideo = numSamples / samplesPerImage * timeImage / 8; % we assume 8 COMPUTATION CORES here
s = seconds(timeVideo); s.Format = 'hh:mm:ss';
fprintf("Estimated Computation Duration for ALL images:" + char(s) + " (hh:mm:ss) with Parallelization\n");


%% 3.) THE VIRTUAL PROJECTION PLANE - raytracing the virtual projection plane
imageDimX = projectionPlaneWidth  / projectionPlaneDelta+1; % the image width
imageDimY = projectionPlaneHeight / projectionPlaneDelta+1; % the image height
disp("Image Dimension: " + imageDimX + "x" + imageDimY);
numImages = floor(numSamples / samplesPerImage)-1; % the number of images

%% 3.1) THE PARRALELIZATION LOOP - windowing over the images
parfor (image = 1:numImages)
    sampleOffset = image * samplesPerImage; % window begin in samples                  % LOOP over the images=windows (PARRALELISATION START)
    yImage = 0;  % counts over the width of the image
    xImage = 0;  % counts over the height of the image
    fprintf("Image " + image + ":");
    IMAGE = zeros (imageDimX, imageDimY); % pre allocate the image array
    for y = -projectionPlaneHeight/2:projectionPlaneDelta:projectionPlaneHeight/2      % LOOP over the image height
        yImage = yImage + 1; % increase image width counter
        for x = -projectionPlaneWidth/2:projectionPlaneDelta:projectionPlaneWidth/2    % LOOP over the image width
            xImage = xImage + 1; % increase image height counter
            distanceSamples = zeros(1,numChannels); % pre-allocate
            %% 3.2) DELAY (extract the distances)
            for m = 1:numChannels                                                      % LOOP over the microphone channels to extarct the delay
                distanceVector = [mic(m).x ,mic(m).y ,0; x ,y ,projectionPlaneDistance];
                distanceMeter = pdist(distanceVector,'euclidean'); % distance from microphone m to the image point in the virtual projection plane
                distanceSamples(m) = distanceMeter / speedOfSound * sampleRate; % distance in samples
            end %channels
            distanceSamples = distanceSamples - min(distanceSamples);
            %% 3.3) SUM (beam one the image point)
            for sample = sampleOffset:sampleOffset+samplesPerImage                     % LOOP over the samples to sum
                sum = 0;
                for m = 1:numChannels                                                  % LOOP over the channels for each sample
                    indexWithDelay = round(sample + distanceSamples(m)); % the shifted index of the saample array for microphone m
                    sum = sum + mic(m).samples(indexWithDelay); % sum for one image point in the projection pane
                end %channels
                IMAGE(xImage,yImage) = IMAGE(xImage,yImage) + abs(sum);
            end %samples
        end %width
        xImage = 0; % new image point
        fprintf('.'); if (mod(yImage,10) == 0) fprintf("%i",yImage); end
    end %height
    %% 3.4) SAVE THE IMAGE
    yImage = 0; % new image row
    fprintf('\n');
    IMAGE = IMAGE - min(IMAGE(:));         % normalize
    IMAGE = IMAGE ./ max(IMAGE(:)) .* 256; % normalize
    filename = [sprintf('img%03d',image) '.png'];
    imwrite(IMAGE, jet(256), ['images/',filename]);
    sound(sin(1:300)); % one beep per image
end %images/offset/windows                                                                                            (PARRALELISATION END)


%% 4.) GENERATE THE MOVIE
% 4.1) oarse the video folder for files
disp("Generate the Movie...");
imageNames = dir(fullfile('images','*.png'));
imageNames = {imageNames.name}';
% 4.2) open the video file
outputVideo = VideoWriter(fullfile('images','AcousticCamera.mp4'),'MPEG-4');
outputVideo.FrameRate = 10;
outputVideo.Quality = 95;
open(outputVideo)
colorMap = jet(256);
% 4.3) save the images to the video file
for ii = 1:length(imageNames) %% loop over the images
    img = imread(fullfile('images',imageNames{ii})); % read one frame (grewyscale)
    writeVideo(outputVideo,im2frame(img,colorMap))   % write the frame with colormap
end
close(outputVideo)
% 4.4) open the video file
implay("images/AcousticCamera.mp4");           % matlab video player
system("open images/AcousticCamera.mp4");      % macos video player


%% 5.) CLEAN UP
%delete('images/*.png')
