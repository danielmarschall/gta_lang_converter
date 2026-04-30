program FxtToolUnicode;

{
  FXT<=>TXT converter for GTA1 and GTA1 London
  by Daniel Marschall
  Revision: 27 April 2026
  Licensed under the terms of the Apache 2.0 license
  Source code compatible with Delphi for Win32/64, and FreePascal for Debian Linux
  More information here: https://misc.daniel-marschall.de/spiele/gta1/format_fxt.html
}

{$IFDEF FPC}
  {$mode delphi}
  {$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
  {$R *.dres}
{$ENDIF}

{$IFDEF FPC}
uses
  SysUtils,
  Classes,
  baseunix,
  ctypes;
{$ELSE}
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  WinApi.Windows;
{$ENDIF}

resourcestring
  S_INVALID_PARAM = 'Invalid parameter/file';
  S_INVALID_FILE = 'File is neither TXT nor FXT';
  S_ERR_S_S = 'ERROR (%s): %s';
  S_WARN_S_S = 'WARNING (%s): %s';
  S_OK_S_S = 'OK: %s => %s';
  {$IFDEF MSWINDOWS}
  S_PRESS_ANY_KEY = 'Press any key to exit.';
  {$ENDIF}
  S_INTRO_1 = 'FXT<>TXT Converter for GTA 1 and GTA London (Unicode Version)';
  S_INTRO_2 = 'by Daniel Marschall';
  S_INTRO_3 = 'Revision: 27 April 2026';
  S_INTRO_4 = 'Licensed under the terms of the Apache 2.0 license';
  S_USAGE = 'Usage:';
  S_IllegalKanji = 'Warning: Illegal character not in Kanji.idx: %s';
  S_IllegalEuropeanChar = 'Warning: Illegal European character: %s';
  SFileNotFound = 'File not found: %s';
  SInvalidKanjiFileSize = 'Invalid Kanji Index size: %s';
  SIconvUnsupportedEncoding = 'Unsupported encoding: %d';
  SIconvOpenFailed = 'iconv_open failed';
  SIconvFailed = 'iconv %s => %s failed. File has probably invalid characters.';

// --- Encoding Stuff

const
  CP_UTF8 = 65001;
  CP_EURO = 1252;
  CP_SJIS = 932;

function MakeEncoding(CodePage: Integer): TEncoding;
begin
  Result := TEncoding.GetEncoding(CodePage);
end;

{$IFDEF FPC}
type
  iconv_t = Pointer;

function iconv_open(tocode, fromcode: PChar): iconv_t; cdecl; external 'c';
function iconv(cd: iconv_t; inbuf: PPChar; inbytesleft: PSizeUInt; outbuf: PPChar; outbytesleft: PSizeUInt): SizeUInt; cdecl; external 'c';
function iconv_close(cd: iconv_t): cint; cdecl; external 'c';

function ConvertWithIconv(const Data: TBytes; SourceEncoding, TargetEncoding: TEncoding): TBytes;

  function EncodingToIconvName(Enc: TEncoding): string;
  begin
    if Enc.CodePage = CP_UTF8 then Exit('UTF-8'); // do not localize
    if Enc.CodePage = CP_SJIS then Exit('CP932'); // do not localize
    if Enc.CodePage = CP_EURO then Exit('CP1252'); // do not localize
    raise Exception.CreateFmt(SIconvUnsupportedEncoding, [Enc.CodePage]);
  end;

var
  cd: iconv_t;
  InBuf, OutBuf: PAnsiChar;
  InBytesLeft, OutBytesLeft: SizeUInt;
  OutSize: SizeUInt;
  PIn, POut: PAnsiChar;
  FromEnc, ToEnc: string;
begin
  Result := nil;

  FromEnc := EncodingToIconvName(SourceEncoding);
  ToEnc := EncodingToIconvName(TargetEncoding);

  cd := iconv_open(PChar(ToEnc), PChar(FromEnc));
  if cd = iconv_t(-1) then
    raise Exception.Create(SIconvOpenFailed);

  try
    InBytesLeft := Length(Data);
    OutSize := InBytesLeft * 4 + 16;

    SetLength(Result, OutSize);

    PIn := PAnsiChar(@Data[0]);
    POut := PAnsiChar(@Result[0]);

    InBuf := PIn;
    OutBuf := POut;
    OutBytesLeft := OutSize;

    while InBytesLeft > 0 do
    begin
      if iconv(cd, @InBuf, @InBytesLeft, @OutBuf, @OutBytesLeft) = SizeUInt(-1) then
        raise Exception.CreateFmt(SIconvFailed, [FromEnc, ToEnc]);
    end;

    SetLength(Result, OutSize - OutBytesLeft);
  finally
    iconv_close(cd);
  end;
end;
{$ENDIF}

// --- Read File Methods

function ReadAllBytesFromFile(const FileName: string): TBytes;
{$IFDEF FPC}
var
  FS: TFileStream;
begin
  Result := nil; // SetLength(Result, 0);
  if not FileExists(FileName) then
    raise Exception.CreateFmt(SFileNotFound, [FileName]);

  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Result[0], FS.Size);
  finally
    FreeAndNil(FS);
  end;
{$ELSE}
begin
  Result := TFile.ReadAllBytes(FileName);
{$ENDIF}
end;

function ReadTextFileWithEncoding(const FileName: string; const SourceEncoding: TEncoding; const TargetEncoding: TEncoding): TBytes;
{$IFDEF FPC}

  function RemovePreamble(const Bytes: TBytes; const Encoding: TEncoding): TBytes;
  var
    Preamble: TBytes;
    I: Integer;
    Matches: Boolean;
  begin
    Result := Bytes;
    Preamble := Encoding.GetPreamble;
    if Length(Preamble) = 0 then
      Exit;
    if Length(Bytes) < Length(Preamble) then
      Exit;
    Matches := True;
    for I := 0 to High(Preamble) do
    begin
      if Bytes[I] <> Preamble[I] then
      begin
        Matches := False;
        Break;
      end;
    end;
    if Matches then
      Result := Copy(Bytes, Length(Preamble), Length(Bytes) - Length(Preamble));
  end;

var
  B: TBytes;
begin
  B := ReadAllBytesFromFile(FileName);
  B := RemovePreamble(B, SourceEncoding);
  Result := ConvertWithIconv(B, SourceEncoding, TargetEncoding);

{$ELSE}
begin
  Result := TargetEncoding.GetBytes(TFile.ReadAllText(FileName, SourceEncoding));
{$ENDIF}
end;

// --- Write File Methods

procedure WriteAllBytesToFile(const FileName: string; Data: TBytes);
{$IFDEF FPC}
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Data) > 0 then
      FS.WriteBuffer(Data[0], Length(Data));
  finally
    FreeAndNil(FS);
  end;
{$ELSE}
begin
  TFile.WriteAllBytes(FileName, Data);
{$ENDIF}
end;

procedure WriteTextFileWithEncoding(const FileName: string; const SourceEncoding: TEncoding; const TargetEncoding: TEncoding; const Data: TBytes);
{$IFDEF FPC}
  function PrependBytes(const Prefix, Data: TBytes): TBytes;
  var
    PrefixLen, DataLen: Integer;
  begin
    Result := nil;

    PrefixLen := Length(Prefix);
    DataLen := Length(Data);

    SetLength(Result, PrefixLen + DataLen);

    if PrefixLen > 0 then
      Move(Prefix[0], Result[0], PrefixLen);

    if DataLen > 0 then
      Move(Data[0], Result[PrefixLen], DataLen);
  end;

var
  ConvertedBytes: TBytes;
begin
  ConvertedBytes := ConvertWithIconv(Data, SourceEncoding, TargetEncoding);
  ConvertedBytes := PrependBytes(TargetEncoding.GetPreamble, ConvertedBytes);
  WriteAllBytesToFile(FileName, ConvertedBytes);
{$ELSE}
begin
  TFile.WriteAllText(FileName, SourceEncoding.GetString(Data), TargetEncoding);
{$ENDIF}
end;

// --- File Detection

type
  TFileEncInfo = record
    IsUtf8: Boolean;
    IsJapanese: Boolean;
    Encoding: TEncoding;
    FileEncoding: TEncoding; // for reading the file
  end;

// Decode UTF-8 sequence and check for CJK (U+3000..U+9FFF, U+F900..U+FAFF)
function IsCJKCodepoint(CP: Cardinal): Boolean;
begin
  Result := ((CP >= $3000) and (CP <= $9FFF)) or
            ((CP >= $F900) and (CP <= $FAFF));
end;

function DetectFileEncoding(const FileName: string): TFileEncInfo;
var
  RawBytes, Sample: TBytes;
  I: Integer;
  HasBOM, IsShiftJIS, HasCJK: Boolean;
  B, B2: Byte;
  CodePoint: Cardinal;
  SJISBytes: Integer;
begin
  Result.IsUtf8 := False;
  Result.IsJapanese := False;
  Result.Encoding := MakeEncoding(CP_EURO);
  Result.FileEncoding := MakeEncoding(CP_EURO);

  RawBytes := ReadAllBytesFromFile(FileName);
  if Length(RawBytes) = 0 then
    Exit;

  // Sample: First 8 KB is enough for heuristics
  if Length(RawBytes) < 8192 then
    SetLength(Sample, Length(RawBytes))
  else
    SetLength(Sample, 8192);
  Move(RawBytes[0], Sample[0], Length(Sample));

  // --- 1. Check BOM ---
  HasBOM := (Length(Sample) >= 3) and
            (Sample[0] = $EF) and (Sample[1] = $BB) and (Sample[2] = $BF);

  if HasBOM then
  begin
    // UTF-8 with BOM: Check contents for CJK
    Result.IsUtf8 := True;
    HasCJK := False;
    I := 3;
    while I < Length(Sample) - 2 do
    begin
      B := Sample[I];
      // 3-Byte UTF-8: $E3..$E9 → CJK-Area
      if (B >= $E3) and (B <= $E9) and
         ((Sample[I+1] and $C0) = $80) and
         ((Sample[I+2] and $C0) = $80) then
      begin
        CodePoint := ((Cardinal(B) and $0F) shl 12) or
                     ((Cardinal(Sample[I+1]) and $3F) shl 6) or
                      (Cardinal(Sample[I+2]) and $3F);
        if IsCJKCodepoint(CodePoint) then
        begin
          HasCJK := True;
          Break;
        end;
      end;
      Inc(I);
    end;
    Result.IsJapanese := HasCJK;
    Result.FileEncoding := MakeEncoding(CP_UTF8);
    if HasCJK then
      Result.Encoding := MakeEncoding(CP_SJIS)
    else
      Result.Encoding := MakeEncoding(CP_EURO);
    Exit;
  end;

  // --- 2. Detect Shift-JIS ---
  // Shift-JIS Lead-Bytes: $81-$9F or $E0-$EF, Trail: $40-$FC (except $7F)
  SJISBytes := 0;
  I := 0;
  while I < Length(Sample) - 1 do
  begin
    B := Sample[I];
    B2 := Sample[I + 1];
    if (((B >= $81) and (B <= $9F)) or ((B >= $E0) and (B <= $EF))) and
       ((B2 >= $40) and (B2 <= $FC) and (B2 <> $7F)) then
    begin
      Inc(SJISBytes, 2);
      Inc(I); // Skip second byte
    end;
    Inc(I);
  end;

  IsShiftJIS := (SJISBytes > Length(Sample) div 5); // >20%

  if IsShiftJIS then
  begin
    Result.IsJapanese := True;
    Result.Encoding := MakeEncoding(CP_SJIS);
    Result.FileEncoding := MakeEncoding(CP_SJIS);
    Exit;
  end;

  // --- 3. Detect UTF-8 without BOM ---
  Result.IsUtf8 := False;
  HasCJK := False;
  I := 0;
  while I < Length(Sample) - 2 do
  begin
    B := Sample[I];
    // 2-Byte: $C2-$DF
    if (B >= $C2) and (B <= $DF) and ((Sample[I+1] and $C0) = $80) then
    begin
      Result.IsUtf8 := True;
      Inc(I, 2);
      Continue;
    end;
    // 3-Byte: $E0-$EF → check for CJK
    if (B >= $E0) and (B <= $EF) and
       ((Sample[I+1] and $C0) = $80) and
       ((Sample[I+2] and $C0) = $80) then
    begin
      Result.IsUtf8 := True;
      CodePoint := ((Cardinal(B) and $0F) shl 12) or
                   ((Cardinal(Sample[I+1]) and $3F) shl 6) or
                    (Cardinal(Sample[I+2]) and $3F);
      if IsCJKCodepoint(CodePoint) then
        HasCJK := True;
      Inc(I, 3);
      Continue;
    end;
    Inc(I);
  end;

  if Result.IsUtf8 then
  begin
    Result.IsJapanese := HasCJK;
    Result.FileEncoding := MakeEncoding(CP_UTF8);
    if HasCJK then
      Result.Encoding := MakeEncoding(CP_SJIS)
    else
      Result.Encoding := MakeEncoding(CP_EURO);
    Exit;
  end;

  // --- 4. ANSI Fallback: only Byte-Statistics ---
  // Middle European ANSI: $80-$FF without Shift-JIS-Pattern → CP1252
  // (IsJapanese stays False, Encoding stays 1252)
end;

// --- Japanese Kanji Methods

function LoadKanjiIdx: TBytes;
{$IFDEF FPC}
var
  FileName: string;
begin
  FileName := ExtractFilePath(ParamStr(0)) + 'KANJI.IDX'; // do not localize
  Result := ReadAllBytesFromFile(FileName);
  if (Length(Result) > 0) and ((Length(Result) mod 2) <> 0) then
    raise Exception.CreateFmt(SInvalidKanjiFileSize, [FileName]);
{$ELSE}
var
  ResStream: TResourceStream;
begin
  ResStream := TResourceStream.Create(HInstance, 'KANJI_IDX', RT_RCDATA); // do not localize
  try
    SetLength(Result, ResStream.Size);
    ResStream.ReadBuffer(Result[0], ResStream.Size);
  finally
    FreeAndNil(ResStream);
  end;
{$ENDIF}
end;

function IsKanjiValid(const Data: TBytes; Value: Word): Boolean;
var
  Offset: Integer;
  Entry: Word;
begin
  Offset := Value * 2;
  if Offset < $FF then Offset := Offset shl 8; // TODO: this is weird! adjust the documentation?!
  if Offset + 1 >= Length(Data) then
    Exit(False);
  Entry := PWord(@Data[Offset])^;
  Result := Entry <> $FFFF;
end;

// --- FXT/TXT Converter Methods

procedure FxtToTxt(const InFile, OutFile: string);
var
  InBytes, OutBytes: TBytes;
  InPos, OutPos: Integer;
  K: Byte;

  function ReadFromInput(var Value: Integer): Boolean;
  begin
    Result := InPos < Length(InBytes);
    if not Result then
      Exit;

    Value := Integer(InBytes[InPos]);

    // Unmask header
    // Note: Further encoding (such as extended charset commands) will come
    //       after the header unmasking! The header unmasking does NOT replace the
    //       next steps. This is wrong in the other converter tools.
    if InPos < 8 then
    begin
      if InPos = 0 then
        K := 100 // LCG seed
      else
        K := (2 * K - 1) mod 256;
      Value := (Value - K + 256) mod 256 + 1; // +1 because we will do -1 in the main method handling
    end;

    Inc(InPos);
  end;

  procedure WriteToOutput(Value: Integer);
  begin
    OutBytes[OutPos] := Byte(Value and $FF);
    Inc(OutPos);
  end;

var
  Value, Tmp: Integer;
  Encoding: TEncoding;
  IsJapanese: Boolean;
begin
  InBytes := ReadAllBytesFromFile(InFile);
  SetLength(OutBytes, Length(InBytes) * 2 + 16); // enough space

  OutPos := 0;
  InPos := 0;
  IsJapanese := False;

  while ReadFromInput(Value) do
  begin
    case Value of
      $00:
        begin
          // 0x00 seems might be the Japanese equivalent to the French 0xC3 code
          // i.e. including and marking an illegal Shift-JIS character
          if not ReadFromInput(Value) then Break;
          WriteToOutput(Value - 1);
          if not ReadFromInput(Value) then Break;
          WriteToOutput(Value - 1);
        end;

      $01:
        begin
          WriteToOutput(13{\r});
          WriteToOutput(10{\n});
        end;

      $84: // GTA London uses this code for Non-English letters (but GTA 1 can use this too)
        begin
          if not ReadFromInput(Value) then Break;
          WriteToOutput(Value + $C0 - 1);
        end;

      $C3:
        begin
          // C3 can be found in FRENCH.FXT to mark illegal characters. See notes below (in TxtToFxt)
          if not ReadFromInput(Value) then Break;
          WriteToOutput(Value - 1);
        end;

      $C4: // GTA1 uses this code for Non-English letters (but GTA London can use this too)
        begin
          if not ReadFromInput(Value) then Break;
          WriteToOutput(Value + $40 - 1);
        end;

      $E0..$FF:
        begin
          // Japanese GTA1 uses the codes $E9 xx yy and $EA xx yy and $EF xx yy
          // The general rule is:
          // For FXT code "$Ez b0 b1":  ShiftJIS = $zFFE - $40*($FF-b0) - ($FF-b1)
          // $Fz does the same as $Ez
          IsJapanese := True;
          Tmp := ((Value and $F) shl 12) + $FFE; // $E9 becomes $9FFE, $EA becomes $AFFE, $EF becomes $FFFE
          if not ReadFromInput(Value) then Break;
          Tmp := Tmp - $40 * ($FF - Value);
          if not ReadFromInput(Value) then Break;
          Tmp := Tmp - ($FF - Value);
          WriteToOutput((Tmp shr 8) and $FF);
          WriteToOutput(Tmp and $FF);
        end;
    else
      WriteToOutput(Value - 1);
    end;
  end;

  if IsJapanese then
    Encoding := MakeEncoding(CP_SJIS)
  else
    Encoding := MakeEncoding(CP_EURO);

  // Make sure the footer is valid
  while (OutPos >= 1) and (OutBytes[OutPos - 1] in [13{\r}, 10{\n}]) do
    Dec(OutPos);
  if (OutPos >= 2) and (OutBytes[OutPos - 2] <> Ord('[')) and (OutBytes[OutPos - 1] <> Ord(']')) then
  begin
    WriteToOutput(13{\r});
    WriteToOutput(10{\n});
    WriteToOutput(Ord('['));
    WriteToOutput(Ord(']'));
  end;

  SetLength(OutBytes, OutPos);
  WriteTextFileWithEncoding(OutFile, Encoding, MakeEncoding(CP_UTF8), OutBytes);

  WriteLn(Format(S_OK_S_S, [InFile, OutFile]));
end;

procedure TxtToFxt(const InFile, OutFile: string; PreferLondonStyle: boolean=true);
var
  InBytes, OutBytes: TBytes;
  InPos, OutPos: Integer;
  K: Integer;

  function ReadFromInput(var Value: Integer): Boolean;
  begin
    Result := InPos < Length(InBytes);
    if not Result then
      Exit;
    Value := Integer(InBytes[InPos]);
    Inc(InPos);
  end;

  procedure WriteToOutput(Value: Integer);
  begin
    // Mask header
    if OutPos < 8 then
    begin
      if OutPos = 0 then
        K := 100 // LCG seed
      else
        K := (2 * K - 1) mod 256;
      Value := (Value + K + 256) mod 256 - 1; // -1 because we did +1 in the main method handling
    end;

    OutBytes[OutPos] := Byte(Value and $FF);
    Inc(OutPos);
  end;

var
  Value: Integer;
  IsJapanese, InName, WasInName: Boolean;
  Info: TFileEncInfo;
  Sjis: Word;
  SjisBase: Integer;
  SjisPrefix: Byte;
  SjisD, SjisX, SjisY: Integer;
  KanjiIdx: TBytes;
begin
  Info := DetectFileEncoding(InFile);

  IsJapanese := Info.IsJapanese;
  if IsJapanese then
    KanjiIdx := LoadKanjiIdx;
  InBytes := ReadTextFileWithEncoding(InFile, Info.FileEncoding, Info.Encoding);
  SetLength(OutBytes, Length(InBytes) * 2 + 16);

  OutPos := 0;
  InPos := 0;
  InName := False;

  while ReadFromInput(Value) do
  begin
    // FRENCH.FXT has an error in the original text data:
    //            It writes 5C 0E 0B 0E 0B 5C, which stands for '[', then 2 line breaks, then '['
    //            This shows: The original Txt-to-Fxt tool didn't translate CRLF to \1\1 when its inside brackets
    //            Note: The game has no problems with this.
    if Value = Ord('[') then
      InName := True;
    WasInName := InName;
    if Value = Ord(']') then
      InName := False;

    if IsJapanese then
    begin
      // Japanese Encoding; detailled description here:
      // https://misc.daniel-marschall.de/spiele/gta1/format_fxt.html
      if ((Value >= $81) and (Value <= $9F)) or
         ((Value >= $E0) and (Value <= $EF)) then
      begin
        Sjis := Word(Value);
        if not ReadFromInput(Value) then
          Break;
        Sjis       := (Sjis shl 8) or Word(Value);
        if not IsKanjiValid(KanjiIdx, Sjis) then
          WriteLn(Format(S_IllegalKanji, ['0x' + IntToHex(Sjis, 4)]));
        SjisBase   := ((Sjis and $F000) + $1000) or $0FFE;
        SjisPrefix := $E0 + (SjisBase shr 12);
        SjisD      := SjisBase - Sjis;
        SjisY      := SjisD mod $40;
        if SjisY < $3F then
          SjisY := SjisY + $40;
        SjisX := (SjisD - SjisY) div $40;
        WriteToOutput(SjisPrefix);
        WriteToOutput($FF - SjisX);
        WriteToOutput($FF - SjisY);
        Continue;
      end
      else
      begin
        if not (Value in [$0A, $0D, $20]) and not IsKanjiValid(KanjiIdx, Value) then
          WriteLn(Format(S_IllegalKanji, ['0x' + IntToHex(Value, 4)]));
      end;
    end
    else
    begin
      // 0xC3 xx is a special case found in the original French translation, where œ is converted to C3 9D,
      // and printed as "!", since œ is not existing in the game font.
      // Theory: In the original development tools, once the TXT-to-FXT converter noticed an illegal character,
      // xx gets encoded as C3 xx+1, making sure the game will print "!", but the editor itself
      // (or TXT-to-FXT converter) can display the original character that was intended by the translator.
      // ...
      // However, "ñ" in French.fxt is also invalid, but it is not encoded as C3 xx !
      if not WasInName and not (Value in [13,10,$1A,$20..$7E,$C0{À},$C1{Á},$C2{Â},$C4{Ä},$C6{Æ},$C7{Ç},$C8{È},$C9{É},$CA{Ê},$CB{Ë},$CC{Ì},$CD{Í},$CE{Î},$CF{Ï},$D2{Ò},$D3{Ó},$D4{Ô},$D6{Ö},$D9{Ù},$DA{Ú},$DB{Û},$DC{Ü},$DF{ß},$E0{à},$E1{á},$E2{â},$E4{ä},$E6{æ},$E7{ç},$E8{è},$E9{é},$EA{ê},$EB{ë},$EC{ì},$ED{í},$EE{î},$EF{ï},$F2{ò},$F3{ó},$F4{ô},$F6{ö},$F9{ù},$FA{ú},$FB{û},$FC{ü}]) then
      begin
        WriteLn(Format(S_IllegalEuropeanChar, ['0x' + IntToHex(Value,2)]));
        if Value = $9C{œ} then
        begin
          WriteToOutput($C3); // unknown why French.fxt does that with œ but not with ñ
          WriteToOutput(Value + 1);
          continue;
        end;
      end;

      // Extended Charset for Middle European GTA
      if Value >= $C0 then
      begin
        if PreferLondonStyle then
        begin
          WriteToOutput($84); // Extended prefix for GTA London (but can be read by GTA1 too)
          Value := Value - $C0;
        end
        else
        begin
          WriteToOutput($C4); // Extended prefix for GTA 1 (but can be read by London too)
          Value := Value - $40;
        end;
      end;
    end;

    if not InName and (Value = 13{\r}) then
      continue
    else if not InName and (Value = 10{\n}) then
      WriteToOutput($01)
    else
      WriteToOutput(Value + 1);
  end;

  // Make sure the footer is valid
  while (OutPos>=1) and (OutBytes[OutPos-1] = $01) do Dec(OutPos);
  if (OutPos>=2) and (OutBytes[OutPos-2] <> Ord('[')+1) and (OutBytes[OutPos-1] <> Ord(']')+1) then
  begin
    WriteToOutput($01);
    WriteToOutput(Ord('[') + 1);
    WriteToOutput(Ord(']') + 1);
  end;

  SetLength(OutBytes, OutPos);
  WriteAllBytesToFile(OutFile, OutBytes);

  WriteLn(Format(S_OK_S_S, [InFile, OutFile]));
end;

// --- Main Methods (CLI)

procedure ShowUsage;
begin
  Writeln(S_INTRO_1);
  Writeln(S_INTRO_2);
  Writeln(S_INTRO_3);
  Writeln(S_INTRO_4);
  Writeln('');
  Writeln(S_USAGE);
  {$IFDEF MSWINDOWS}
  Writeln('  '+UpperCase(ExtractFileName(ParamStr(0)))+' input.fxt');
  Writeln('  '+UpperCase(ExtractFileName(ParamStr(0)))+' input.txt');
  {$ELSE}
  Writeln('  ./'+ExtractFileName(ParamStr(0))+' input.fxt [outfile.txt]');
  Writeln('  ./'+ExtractFileName(ParamStr(0))+' input.txt [outfile.fxt]');
  {$ENDIF}
  Writeln;
end;

function CompareFiles(const File1, File2: string): Boolean;
const
  BufferSize = 64 * 1024; // 64 KB
var
  Stream1, Stream2: TFileStream;
  Buffer1, Buffer2: TBytes;
  Read1, Read2: Integer;
begin
  Result := False;

  if not FileExists(File1) then
  begin
    Writeln(Format('Error: File not found: %s', [File1]));
    Exit;
  end;

  if not FileExists(File2) then
  begin
    Writeln(Format('Error: File not found: %s', [File2]));
    Exit;
  end;

  Stream1 := TFileStream.Create(File1, fmOpenRead or fmShareDenyWrite);
  Stream2 := TFileStream.Create(File2, fmOpenRead or fmShareDenyWrite);
  try
    // Check file size first
    if Stream1.Size <> Stream2.Size then
    begin
      Writeln(Format('TEST FAILURE: File size differs: %s %d <> %s %d)',
        [File1, Stream1.Size, File2, Stream2.Size]));
      Exit;
    end;

    SetLength(Buffer1, BufferSize);
    SetLength(Buffer2, BufferSize);

    repeat
      Read1 := Stream1.Read(Buffer1[0], BufferSize);
      Read2 := Stream2.Read(Buffer2[0], BufferSize);

      if Read1 <> Read2 then
      begin
        Writeln('TEST FAILURE: File contents differ '+File1+' <=> '+File2);
        Exit;
      end;

      if not CompareMem(@Buffer1[0], @Buffer2[0], Read1) then
      begin
        Writeln('TEST FAILURE: File contents differ '+File1+' <=> '+File2);
        Exit;
      end;
    until Read1 = 0;

    WriteLn('OK: (Binary comparison '+File1+' <=> '+File2+')');
    Result := True;
  finally
    FreeAndNil(Stream1);
    FreeAndNil(Stream2);
  end;
end;

procedure Testcases;
const
  {$IFDEF MSWINDOWS}
  TestDir = 'fxt_original\';
  {$ELSE}
  TestDir = 'fxt_original/';
  {$ENDIF}
begin
  FxtToTxt(TestDir + 'ENGLISH.FXT', TestDir + 'ENGLISH.TXT');
  TxtToFxt(TestDir + 'ENGLISH.TXT', TestDir + 'ENGLISH2.FXT', false);
  FxtToTxt(TestDir + 'ENGLISH2.FXT', TestDir + 'ENGLISH2.TXT');
  CompareFiles(TestDir + 'ENGLISH.TXT', TestDir + 'ENGLISH2.TXT');
  CompareFiles(TestDir + 'ENGLISH.FXT', TestDir + 'ENGLISH2.FXT');

  FxtToTxt(TestDir + 'ENGUK.FXT', TestDir + 'ENGUK.TXT');
  TxtToFxt(TestDir + 'ENGUK.TXT', TestDir + 'ENGUK2.FXT', true);
  FxtToTxt(TestDir + 'ENGUK2.FXT', TestDir + 'ENGUK2.TXT');
  CompareFiles(TestDir + 'ENGUK.TXT', TestDir + 'ENGUK2.TXT');
  CompareFiles(TestDir + 'ENGUK.FXT', TestDir + 'ENGUK2.FXT');

  FxtToTxt(TestDir + 'ENGUKE.FXT', TestDir + 'ENGUKE.TXT');
  TxtToFxt(TestDir + 'ENGUKE.TXT', TestDir + 'ENGUKE2.FXT', true);
  FxtToTxt(TestDir + 'ENGUKE2.FXT', TestDir + 'ENGUKE2.TXT');
  CompareFiles(TestDir + 'ENGUKE.TXT', TestDir + 'ENGUKE2.TXT');
  CompareFiles(TestDir + 'ENGUKE.FXT', TestDir + 'ENGUKE2.FXT');

  FxtToTxt(TestDir + 'GERMAN.FXT', TestDir + 'GERMAN.TXT');
  TxtToFxt(TestDir + 'GERMAN.TXT', TestDir + 'GERMAN2.FXT', false);
  FxtToTxt(TestDir + 'GERMAN2.FXT', TestDir + 'GERMAN2.TXT');
  CompareFiles(TestDir + 'GERMAN.TXT', TestDir + 'GERMAN2.TXT');
  CompareFiles(TestDir + 'GERMAN.FXT', TestDir + 'GERMAN2.FXT');

  FxtToTxt(TestDir + 'GERUK.FXT', TestDir + 'GERUK.TXT');
  TxtToFxt(TestDir + 'GERUK.TXT', TestDir + 'GERUK2.FXT', true);
  FxtToTxt(TestDir + 'GERUK2.FXT', TestDir + 'GERUK2.TXT');
  CompareFiles(TestDir + 'GERUK.TXT', TestDir + 'GERUK2.TXT');
  CompareFiles(TestDir + 'GERUK.FXT', TestDir + 'GERUK2.FXT');

  FxtToTxt(TestDir + 'geruke_AutoTranslated.FXT', TestDir + 'geruke_AutoTranslated.TXT');
  TxtToFxt(TestDir + 'geruke_AutoTranslated.TXT', TestDir + 'geruke_AutoTranslated2.FXT', true);
  FxtToTxt(TestDir + 'geruke_AutoTranslated2.FXT', TestDir + 'geruke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'geruke_AutoTranslated.TXT', TestDir + 'geruke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'geruke_AutoTranslated.FXT', TestDir + 'geruke_AutoTranslated2.FXT');

  FxtToTxt(TestDir + 'FRENCH.FXT', TestDir + 'FRENCH.TXT');
  TxtToFxt(TestDir + 'FRENCH.TXT', TestDir + 'FRENCH2.FXT', false);
  FxtToTxt(TestDir + 'FRENCH2.FXT', TestDir + 'FRENCH2.TXT');
  CompareFiles(TestDir + 'FRENCH.TXT', TestDir + 'FRENCH2.TXT');
  CompareFiles(TestDir + 'FRENCH.FXT', TestDir + 'FRENCH2.FXT');

  (*
  FxtToTxt(TestDir + 'FREUK.FXT', TestDir + 'FREUK.TXT');
  TxtToFxt(TestDir + 'FREUK.TXT', TestDir + 'FREUK2.FXT', true);
  FxtToTxt(TestDir + 'FREUK2.FXT', TestDir + 'FREUK2.TXT');
  CompareFiles(TestDir + 'FREUK.TXT', TestDir + 'FREUK2.TXT');
  CompareFiles(TestDir + 'FREUK.FXT', TestDir + 'FREUK2.FXT');
  *)

  FxtToTxt(TestDir + 'FREUK_AutoTranslated.FXT', TestDir + 'FREUK_AutoTranslated.TXT');
  TxtToFxt(TestDir + 'FREUK_AutoTranslated.TXT', TestDir + 'FREUK_AutoTranslated2.FXT', true);
  FxtToTxt(TestDir + 'FREUK_AutoTranslated2.FXT', TestDir + 'FREUK_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'FREUK_AutoTranslated.TXT', TestDir + 'FREUK_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'FREUK_AutoTranslated.FXT', TestDir + 'FREUK_AutoTranslated2.FXT');

  FxtToTxt(TestDir + 'freuke_AutoTranslated.FXT', TestDir + 'freuke_AutoTranslated.TXT');
  TxtToFxt(TestDir + 'freuke_AutoTranslated.TXT', TestDir + 'freuke_AutoTranslated2.FXT', true);
  FxtToTxt(TestDir + 'freuke_AutoTranslated2.FXT', TestDir + 'freuke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'freuke_AutoTranslated.TXT', TestDir + 'freuke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'freuke_AutoTranslated.FXT', TestDir + 'freuke_AutoTranslated2.FXT');

  FxtToTxt(TestDir + 'ITALIAN.FXT', TestDir + 'ITALIAN.TXT');
  TxtToFxt(TestDir + 'ITALIAN.TXT', TestDir + 'ITALIAN2.FXT', false);
  FxtToTxt(TestDir + 'ITALIAN2.FXT', TestDir + 'ITALIAN2.TXT');
  CompareFiles(TestDir + 'ITALIAN.TXT', TestDir + 'ITALIAN2.TXT');
  CompareFiles(TestDir + 'ITALIAN.FXT', TestDir + 'ITALIAN2.FXT');

  FxtToTxt(TestDir + 'ITAUK.FXT', TestDir + 'ITAUK.TXT');
  TxtToFxt(TestDir + 'ITAUK.TXT', TestDir + 'ITAUK2.FXT', true);
  FxtToTxt(TestDir + 'ITAUK2.FXT', TestDir + 'ITAUK2.TXT');
  CompareFiles(TestDir + 'ITAUK.TXT', TestDir + 'ITAUK2.TXT');
  CompareFiles(TestDir + 'ITAUK.FXT', TestDir + 'ITAUK2.FXT');

  FxtToTxt(TestDir + 'itauke_AutoTranslated.FXT', TestDir + 'itauke_AutoTranslated.TXT');
  TxtToFxt(TestDir + 'itauke_AutoTranslated.TXT', TestDir + 'itauke_AutoTranslated2.FXT', true);
  FxtToTxt(TestDir + 'itauke_AutoTranslated2.FXT', TestDir + 'itauke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'itauke_AutoTranslated.TXT', TestDir + 'itauke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'itauke_AutoTranslated.FXT', TestDir + 'itauke_AutoTranslated2.FXT');

  FxtToTxt(TestDir + 'SPECIAL.FXT', TestDir + 'SPECIAL.TXT');
  TxtToFxt(TestDir + 'SPECIAL.TXT', TestDir + 'SPECIAL2.FXT', false);
  FxtToTxt(TestDir + 'SPECIAL2.FXT', TestDir + 'SPECIAL2.TXT');
  CompareFiles(TestDir + 'SPECIAL.TXT', TestDir + 'SPECIAL2.TXT');
  CompareFiles(TestDir + 'SPECIAL.FXT', TestDir + 'SPECIAL2.FXT');

  FxtToTxt(TestDir + 'SPEUK.FXT', TestDir + 'SPEUK.TXT');
  TxtToFxt(TestDir + 'SPEUK.TXT', TestDir + 'SPEUK2.FXT', true);
  FxtToTxt(TestDir + 'SPEUK2.FXT', TestDir + 'SPEUK2.TXT');
  CompareFiles(TestDir + 'SPEUK.TXT', TestDir + 'SPEUK2.TXT');
  CompareFiles(TestDir + 'SPEUK.FXT', TestDir + 'SPEUK2.FXT');

  FxtToTxt(TestDir + 'JAPANESE.FXT', TestDir + 'JAPANESE.TXT');
  TxtToFxt(TestDir + 'JAPANESE.TXT', TestDir + 'JAPANESE2.FXT', false);
  FxtToTxt(TestDir + 'JAPANESE2.FXT', TestDir + 'JAPANESE2.TXT');
  CompareFiles(TestDir + 'JAPANESE.TXT', TestDir + 'JAPANESE2.TXT');
  CompareFiles(TestDir + 'JAPANESE.FXT', TestDir + 'JAPANESE2.FXT');

  FxtToTxt(TestDir + 'JAPUK.FXT', TestDir + 'JAPUK.TXT');
  TxtToFxt(TestDir + 'JAPUK.TXT', TestDir + 'JAPUK2.FXT', false);
  FxtToTxt(TestDir + 'JAPUK2.FXT', TestDir + 'JAPUK2.TXT');
  CompareFiles(TestDir + 'JAPUK.TXT', TestDir + 'JAPUK2.TXT');
  CompareFiles(TestDir + 'JAPUK.FXT', TestDir + 'JAPUK2.FXT');

  FxtToTxt(TestDir + 'japuke_AutoTranslated.FXT', TestDir + 'japuke_AutoTranslated.TXT');
  TxtToFxt(TestDir + 'japuke_AutoTranslated.TXT', TestDir + 'japuke_AutoTranslated2.FXT', false);
  FxtToTxt(TestDir + 'japuke_AutoTranslated2.FXT', TestDir + 'japuke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'japuke_AutoTranslated.TXT', TestDir + 'japuke_AutoTranslated2.TXT');
  CompareFiles(TestDir + 'japuke_AutoTranslated.FXT', TestDir + 'japuke_AutoTranslated2.FXT');

  // ---

  FxtToTxt(TestDir + 'DOSDATA_ENGLISH.FXT', TestDir + 'DOSDATA_ENGLISH.TXT');
  TxtToFxt(TestDir + 'DOSDATA_ENGLISH.TXT', TestDir + 'DOSDATA_ENGLISH2.FXT', false);
  FxtToTxt(TestDir + 'DOSDATA_ENGLISH2.FXT', TestDir + 'DOSDATA_ENGLISH2.TXT');
  CompareFiles(TestDir + 'DOSDATA_ENGLISH.TXT', TestDir + 'DOSDATA_ENGLISH2.TXT');
  CompareFiles(TestDir + 'DOSDATA_ENGLISH.FXT', TestDir + 'DOSDATA_ENGLISH2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_enguk.fxt', TestDir + 'DOSDATA_ENGUK.TXT');
  TxtToFxt(TestDir + 'DOSDATA_ENGUK.TXT', TestDir + 'DOSDATA_ENGUK2.FXT', true);
  FxtToTxt(TestDir + 'DOSDATA_ENGUK2.FXT', TestDir + 'DOSDATA_ENGUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_ENGUK.TXT', TestDir + 'DOSDATA_ENGUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_enguk.fxt', TestDir + 'DOSDATA_ENGUK2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_GERMAN.FXT', TestDir + 'DOSDATA_GERMAN.TXT');
  TxtToFxt(TestDir + 'DOSDATA_GERMAN.TXT', TestDir + 'DOSDATA_GERMAN2.FXT', false);
  FxtToTxt(TestDir + 'DOSDATA_GERMAN2.FXT', TestDir + 'DOSDATA_GERMAN2.TXT');
  CompareFiles(TestDir + 'DOSDATA_GERMAN.TXT', TestDir + 'DOSDATA_GERMAN2.TXT');
  CompareFiles(TestDir + 'DOSDATA_GERMAN.FXT', TestDir + 'DOSDATA_GERMAN2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_geruk.fxt', TestDir + 'DOSDATA_GERUK.TXT');
  TxtToFxt(TestDir + 'DOSDATA_GERUK.TXT', TestDir + 'DOSDATA_GERUK2.FXT', true);
  FxtToTxt(TestDir + 'DOSDATA_GERUK2.FXT', TestDir + 'DOSDATA_GERUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_GERUK.TXT', TestDir + 'DOSDATA_GERUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_geruk.fxt', TestDir + 'DOSDATA_GERUK2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_FRENCH.FXT', TestDir + 'DOSDATA_FRENCH.TXT');
  TxtToFxt(TestDir + 'DOSDATA_FRENCH.TXT', TestDir + 'DOSDATA_FRENCH2.FXT', false);
  FxtToTxt(TestDir + 'DOSDATA_FRENCH2.FXT', TestDir + 'DOSDATA_FRENCH2.TXT');
  CompareFiles(TestDir + 'DOSDATA_FRENCH.TXT', TestDir + 'DOSDATA_FRENCH2.TXT');
  CompareFiles(TestDir + 'DOSDATA_FRENCH.FXT', TestDir + 'DOSDATA_FRENCH2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_freuk.fxt', TestDir + 'DOSDATA_FREUK.TXT');
  TxtToFxt(TestDir + 'DOSDATA_FREUK.TXT', TestDir + 'DOSDATA_FREUK2.FXT', true);
  FxtToTxt(TestDir + 'DOSDATA_FREUK2.FXT', TestDir + 'DOSDATA_FREUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_FREUK.TXT', TestDir + 'DOSDATA_FREUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_freuk.fxt', TestDir + 'DOSDATA_FREUK2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_ITALIAN.FXT', TestDir + 'DOSDATA_ITALIAN.TXT');
  TxtToFxt(TestDir + 'DOSDATA_ITALIAN.TXT', TestDir + 'DOSDATA_ITALIAN2.FXT', false);
  FxtToTxt(TestDir + 'DOSDATA_ITALIAN2.FXT', TestDir + 'DOSDATA_ITALIAN2.TXT');
  CompareFiles(TestDir + 'DOSDATA_ITALIAN.TXT', TestDir + 'DOSDATA_ITALIAN2.TXT');
  CompareFiles(TestDir + 'DOSDATA_ITALIAN.FXT', TestDir + 'DOSDATA_ITALIAN2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_itauk.fxt', TestDir + 'DOSDATA_ITAUK.TXT');
  TxtToFxt(TestDir + 'DOSDATA_ITAUK.TXT', TestDir + 'DOSDATA_ITAUK2.FXT', true);
  FxtToTxt(TestDir + 'DOSDATA_ITAUK2.FXT', TestDir + 'DOSDATA_ITAUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_ITAUK.TXT', TestDir + 'DOSDATA_ITAUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_itauk.fxt', TestDir + 'DOSDATA_ITAUK2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_JAPAN.FXT', TestDir + 'DOSDATA_JAPAN.TXT');
  TxtToFxt(TestDir + 'DOSDATA_JAPAN.TXT', TestDir + 'DOSDATA_JAPAN2.FXT', true);
  FxtToTxt(TestDir + 'DOSDATA_JAPAN2.FXT', TestDir + 'DOSDATA_JAPAN2.TXT');
  CompareFiles(TestDir + 'DOSDATA_JAPAN.TXT', TestDir + 'DOSDATA_JAPAN2.TXT');
  CompareFiles(TestDir + 'DOSDATA_JAPAN.FXT', TestDir + 'DOSDATA_JAPAN2.FXT');

  FxtToTxt(TestDir + 'DOSDATA_japuk.fxt', TestDir + 'DOSDATA_JAPUK.TXT');
  TxtToFxt(TestDir + 'DOSDATA_JAPUK.TXT', TestDir + 'DOSDATA_JAPUK2.FXT', true);
  FxtToTxt(TestDir + 'DOSDATA_JAPUK2.FXT', TestDir + 'DOSDATA_JAPUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_JAPUK.TXT', TestDir + 'DOSDATA_JAPUK2.TXT');
  CompareFiles(TestDir + 'DOSDATA_japuk.fxt', TestDir + 'DOSDATA_JAPUK2.FXT');

  {$IFDEF MSWINDOWS}
  WriteLn(S_PRESS_ANY_KEY);
  ReadLn;
  exit;
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}
procedure ProcessFile(const InFile: string; var RequirePause: boolean);
begin
  try
         if ExtractFileExt(InFile)         = '.fxt'  then FxtToTxt(InFile, ChangeFileExt(InFile, '.txt')) // do not localize
    else if ExtractFileExt(InFile)         = '.FXT'  then FxtToTxt(InFile, ChangeFileExt(InFile, '.TXT')) // do not localize
    else if SameText(ExtractFileExt(InFile), '.fxt') then FxtToTxt(InFile, ChangeFileExt(InFile, '.txt')) // do not localize
    else if ExtractFileExt(InFile)         = '.txt'  then TxtToFxt(InFile, ChangeFileExt(InFile, '.fxt')) // do not localize
    else if ExtractFileExt(InFile)         = '.TXT'  then TxtToFxt(InFile, ChangeFileExt(InFile, '.FXT')) // do not localize
    else if SameText(ExtractFileExt(InFile), '.txt') then TxtToFxt(InFile, ChangeFileExt(InFile, '.fxt')) // do not localize
    else
    begin
      if FileExists(InFile) then
        raise Exception.Create(S_INVALID_FILE)
      else
        raise Exception.Create(S_INVALID_PARAM);
    end;
  except
    on E: Exception do
    begin
      WriteLn(Format(S_ERR_S_S, [InFile, E.Message]));
      RequirePause := true;
    end;
  end;
end;

procedure ExpandAndProcess(const AArg: string; var RequirePause: boolean);
var
  DirPart, Pattern: string;
  Files: TArray<string>;
  FileName: string;
begin
  if (Pos('*', AArg) > 0) or (Pos('?', AArg) > 0) then
  begin
    DirPart := ExtractFilePath(AArg);
    Pattern := ExtractFileName(AArg);

    if DirPart = '' then
      DirPart := GetCurrentDir;

    Files := TDirectory.GetFiles(DirPart, Pattern, TSearchOption.soTopDirectoryOnly);

    for FileName in Files do
      ProcessFile(FileName, RequirePause);
  end
  else
  begin
    ProcessFile(ExpandFileName(AArg), RequirePause);
  end;
end;
{$ENDIF}

procedure Main;
{$IFDEF MSWINDOWS}
var
  i: integer;
  RequirePause: boolean;
begin
  if ParamCount < 1 then
  begin
    RequirePause := true;
    ShowUsage;
  end
  else
  begin
    RequirePause := false;
    for i := 1 to ParamCount do
    begin
      if ParamStr(i) = 'TEST' then // do not localize
      begin
        try
          Testcases
        except
          on E: Exception do
          begin
            WriteLn(Format('Testcases Exception: %s', [e.Message]));
            RequirePause := true;
          end;
        end;
      end
      else
      ExpandAndProcess(ParamStr(i), RequirePause);
    end;
  end;

  if RequirePause then
  begin
    WriteLn(S_PRESS_ANY_KEY);
    ReadLn;
  end;
{$ELSE}
var
  InFile, OutFile, Ext: string;
begin
  if ParamCount < 1 then
  begin
    ShowUsage;
    Exit;
  end;

  InFile := ParamStr(1);
  if InFile = 'TEST' then // do not localize
  begin
    Testcases;
    Exit;
  end;
  if ParamCount >= 2 then
    OutFile := ParamStr(2)
  else
  begin
    Ext := LowerCase(ExtractFileExt(InFile));
    if Ext = '.fxt' then // do not localize
      OutFile := ChangeFileExt(InFile, '.txt') // do not localize
    else if Ext = '.txt' then // do not localize
      OutFile := ChangeFileExt(InFile, '.fxt') // do not localize
    else
      raise Exception.Create(S_INVALID_FILE);
  end;

  Ext := LowerCase(ExtractFileExt(InFile));
  if Ext = '.fxt' then // do not localize
    FxtToTxt(InFile, OutFile)
  else if Ext = '.txt' then // do not localize
    TxtToFxt(InFile, OutFile)
  else
    raise Exception.Create(S_INVALID_FILE);
{$ENDIF}
end;

begin
  try
    Main;
  except
    on E: Exception do
    begin
      Writeln(Format(S_ERR_S_S, [E.ClassName, E.Message]));
      {$IFDEF FPC}
      Halt(1);
      {$ELSE}
      ExitCode := 1;
      {$ENDIF}
    end;
  end;
end.
