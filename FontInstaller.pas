unit FontInstaller;
interface

uses System.SysUtils, System.Classes, System.Types,
  System.Generics.Collections

  {$IFDEF MSWINDOWS}
  , WinAPI.Windows, Winapi.Messages
  {$ELSEIF MACOS}
  , Macapi.CoreFoundation, Macapi.Foundation
  {$ENDIF}
  ;

type
  TSaveFontCalback = reference to function(const resStream: TResourceStream; var fileName: string): Boolean;

  TFontInstaller = class
  private
    class var TempPath: string;
    class var LoadedFonts: TDictionary<string, string>;
    class var Debug: Boolean;

    {$IFDEF MSWINDOWS}
    //class function EnumFontsProc(var logFont: TLogFont; var textMetric: TTextMetric; fontType: Integer; Data: Pointer): Integer; stdcall;
    class procedure CollectFonts(fontList: TStringList);
    class function SaveFont(const resStream: TResourceStream; var fileName: string): Boolean;
    class function EachFontResources(callback: TSaveFontCalback): Boolean; overload;
    class function EachFontResources(const fontIDList: TArray<string>; callback: TSaveFontCalback): Boolean; overload;
    {$ELSEIF MACOS}
    class function NSUserName: Pointer; cdecl; external '/System/Library/Frameworks/Foundation.framework/Foundation' name _PU + 'NSUserName';
    class function SaveFont(const resStream: TResourceStream; var fileName: string): Boolean;
    class function EachFontResources(const fontIDList: TArray<string>; callback: TSaveFontCalback): Boolean; overload;
    {$ENDIF}
  published
    class constructor Create;
  public
    class function LoadTemporaryFonts(const fontIDList: TArray<string>{$IFDEF MSWINDOWS} = []{$ENDIF}): Boolean;
    class function UnLoadTemporaryFonts: Boolean;
    class function IsKnownFont(const font: string): Boolean;
    class procedure GetLoadedFonts(toList: TStrings); overload;
    class function GetLoadedFonts: TStringList; overload;
    class function FontCount: Integer;
  end;

implementation

uses
  {$IFDEF IS_FMX}
  FMX.Dialogs, FMX.Canvas.D2D {$IFDEF MSWINDOWS}, FMX.Platform.win{$ENDIF}
  {$ELSE}
  VCL.Dialogs
  {$ENDIF}
  ;

class constructor TFontInstaller.Create;
begin
  inherited;

  Debug := False;
  LoadedFonts := TDictionary<string, string>.Create;

  {$IFDEF MSWINDOWS}
  SetLength(TempPath, 256);
  SetLength(TempPath, GetTempPath(256, @TempPath[1]));
  if (TempPath <> '') and (TempPath[Length(TempPath)] <> '\') then TempPath := TempPath + '\';
  {$ELSEIF MACOS}
  FTempPath := '/Users/' + TNSString.Wrap(NSUserName).UTF8String + '/Library/Fonts/';
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}

{Fonts from System}
class procedure TFontInstaller.CollectFonts(FontList: TStringList);

  function enumFontsProc(var LogFont: TLogFont; var textMetric: TTextMetric; FontType: Integer; Data: Pointer): Integer;
  var
    S: TStrings;
    Temp: string;
  begin
    S := TStrings(Data);
    Temp := LogFont.lfFaceName;
    if (S.Count = 0) or (AnsiCompareText(S[S.Count - 1], Temp) <> 0) then S.Add(Temp);
    Result := 1;
  end;

var
  DC: WinAPI.Windows.HDC;
  LFont: TLogFont;
begin
  DC := GetDC(0);
  FillChar(LFont, SizeOf(LFont), 0);
  LFont.lfCharset := DEFAULT_CHARSET;
  EnumFontFamiliesEx(DC, LFont, @enumFontsProc, WinAPI.Windows.LPARAM(FontList), 0);
  ReleaseDC(0, DC);
end;

{Extract font Resources
  @only Windows }
class function TFontInstaller.EachFontResources(callback: TSaveFontCalback): Boolean;
var
  resStream: TResourceStream;
  fontID: Integer;
  fontName, fileName: string;
begin
  Result := False;
  fontID := 1;

  while FindResource(hinstance, PChar(fontID), RT_FONT) <> 0 do
  begin
    resStream := TResourceStream.CreateFromID(hinstance, fontID, RT_FONT);
    try
      fontName := 'FONT_' + IntToStr(fontID);
      fileName := fontName;

      if callback(resStream, fileName) then
      begin
        Result := True;
        LoadedFonts.Add(fontName, fileName);
      end;
    finally
      FreeAndNil(resStream);
    end;

    Inc(fontID);
  end;
end;

{Save font}
class function TFontInstaller.SaveFont(const resStream: TResourceStream; var fileName: string): Boolean;

  function getTempFileNameWithExt(const fileName: string): string;
  var
    XCount: Integer;
    fullPath: String;
  begin
    XCount := 99;
    fullPath := TempPath + 'FontTemp_' + fileName;

    Result := fullPath + '.ttf';

    while (FileExists(Result)) and not (System.SysUtils.DeleteFile(Result)) do
    begin
      Inc(XCount);
      Result := fullPath + '_' + IntToHex(XCount, 3) + '.ttf';
    end;
  end;

{$IFNDEF IS_FMX}
var
  fontsCount: DWORD;
  fontInt: Integer;
{$ENDIF}
begin
  Result := False;

  {Only for VCL - try load font to Memory}
  {$IFNDEF IS_FMX}
  fontInt := 0;
  fontsCount := 0;

  Result := (AddFontMemResourceEx(resStream.Memory, resStream.Size, nil , @fontsCount) <> 0);
  {$ENDIF}

  {Save font to Temp file}
  if not (Result) then
  begin
    fileName := getTempFileNameWithExt(fileName);

    resStream.SaveToFile(fileName);
    Result := (AddFontResourceEx(PChar(fileName), FR_NOT_ENUM, nil) <> 0);
  end
  else fileName := '';

  if not (Result) and (Debug) then ShowMessage('Font not loaded!');
end;

{Load fonts from Resources}
class function TFontInstaller.LoadTemporaryFonts(const fontIDList: TArray<string> = []): Boolean;
var
  resStream: TResourceStream;
  fileName: string;
begin
  Result := False;

  if Assigned(fontIDList) and (Length(fontIDList) > 0) then Result := EachFontResources(fontIDList, SaveFont)
  else Result := EachFontResources(SaveFont);

  if not (Result) then Exit;

  PostMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0); // I don't think these are needed but it seems like good form
  PostMessage(ApplicationHWnd, WM_FONTCHANGE, 0, 0); // Went even more specific and sent it directly to the application

  {$IFDEF IS_FMX}
  try
    UnregisterCanvasClasses;
    RegisterCanvasClasses;
  except end;
  {$ENDIF}
end;

{$ELSEIF MACOS}
{Load fonts from Resources}
class function TFontInstaller.LoadTemporaryFonts(const fontIDList: TArray<string>): Boolean;
var
  resStream: TResourceStream;
  fileName: string;
begin
  Result := False;
  if not Assigned(FLoadedFonts) then FLoadedFonts := TStringList.Create;

  Result := EachFontResources(fontIDList, function(resStream: TResourceStream; fileName: string): Boolean
  begin
    fileName := FTempPath + 'FontTemp_' + fileName;

    resStream.SaveToFile(fileName);
    Result := FileExists(fileName);
  end);

  if not (Result) then Exit;

  {$IFDEF IS_FMX}
  try
    UnregisterCanvasClasses;
    RegisterCanvasClasses;
  except end;
  {$ENDIF}
end;

{$ENDIF}

{Extract font Resources}
class function TFontInstaller.EachFontResources(const fontIDList: TArray<string>; callback: TSaveFontCalback): Boolean;
var
  resStream: TResourceStream;
  i: Integer;
  fontName, fileName: string;
begin
  Result := False;

  for i := 0 to High(fontIDList) do
  begin
    fontName := fontIDList[i];

    if FindResource(hinstance, PChar(fontName), RT_RCDATA) <> 0 then
    begin
      resStream := TResourceStream.Create(hinstance, fontName, RT_RCDATA);
      try
        fileName := fontName;

        if callback(resStream, fileName) then
        begin
          Result := True;
          LoadedFonts.Add(fontName, fileName);
        end;
      finally
        FreeAndNil(resStream);
      end;
    end;
  end;
end;

{UnLoad fonts from Resources}
class function TFontInstaller.UnloadTemporaryFonts: Boolean;
var
  i: Integer;
  fileName: string;
begin
  if not (Assigned(LoadedFonts)) then Exit(False);
  
  for i := LoadedFonts.Count - 1 downto 0 do
  begin
    fileName := LoadedFonts.Values.ToArray[i];

    if fileName <> '' then
    begin
      {$IFDEF MSWINDOWS}
      if not (RemoveFontResourceEx(PChar(fileName), FR_NOT_ENUM, nil)) and (Debug) then ShowMessage('Font not removed!');

      PostMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
      PostMessage(ApplicationHWnd, WM_FONTCHANGE, 0, 0); // Went even more specific and sent it directly to the application
      {$ENDIF}

      {Refresh}
      {$IFDEF IS_FMX}
      try
        UnregisterCanvasClasses;
        RegisterCanvasClasses;
      except end;
      {$ENDIF}

      {Remove file}
      if not (System.SysUtils.DeleteFile(fileName)) and (Debug) then ShowMessage('Font file not removed!');
    end;

    {Remove font from list}
    LoadedFonts.Remove(LoadedFonts.Keys.ToArray[i]);
  end;

  {Destroy list}
  FreeAndNil(LoadedFonts);
end;

{Check font in list}
class function TFontInstaller.IsKnownFont(const font: string): Boolean;
var
  availableFonts: TStringList;
begin
  {$IFDEF MSWINDOWS}
  availableFonts := TStringList.Create;
  try
    CollectFonts(availableFonts);

    Result := availableFonts.IndexOf(font) > -1;
  finally
    FreeAndNil(availableFonts);
  end;
  {$ELSE}
  Result := FLoadedFonts.ContainsKey(font);
  {$ENDIF}
end;

{Get loaded fonts}
class procedure TFontInstaller.GetLoadedFonts(toList: TStrings);
var
  i: Integer;
begin
  if not (Assigned(LoadedFonts)) then Exit;

  toList.Clear;
  for i := 0 to LoadedFonts.Count - 1 do toList.Add(LoadedFonts.Keys.ToArray[i]);
end;

{Get loaded fonts}
class function TFontInstaller.GetLoadedFonts: TStringList;
begin
  Result := TStringList.Create;
  GetLoadedFonts(Result);
end;

{Count of loaded fonts}
class function TFontInstaller.FontCount: Integer;
begin
  Result := LoadedFonts.Count;
end;

initialization
finalization
  TFontInstaller.UnLoadTemporaryFonts;
end.
