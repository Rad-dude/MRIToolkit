%%%$ Included in MRIToolkit (https://github.com/delucaal/MRIToolkit) %%%%%% Alberto De Luca - alberto@isi.uu.nl $%%%%%% Distributed under the terms of LGPLv3  %%%
%%% Distributed under the terms of LGPLv3  %%%
function str = concatpath(varargin)
%CONCATPATH  Concatenate file parts with correct file separator.
%		STR = CONCATPATH(STR1, STR2, ...) concatenates file/path parts with the
%		system file separator.
%
%		Example:
%		drive = 'C:';
%		fileName = 'test.txt';
%		fullFileName = concatpath(drive, 'My documents', fileName);
%	
%		Markus Buehren
%		Last modified 05.04.2009
%
%		See also FULLFILE, FILESEP, CHOMPSEP.

str = '';
for n=1:nargin
	curStr = varargin{n};
	str = fullfile(str, chompsep(curStr));
end

if ispc
  str = strrep(str, '/', '\');
else
  str = strrep(str, '\', '/');
end  