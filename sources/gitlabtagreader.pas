{*
 *  Copyright (C) 2024  Uwe Merker
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 *}
unit GitLabTagReader;

{$mode ObjFPC}
{$H+}
{$ModeSwitch arrayoperators}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

function GetTagList(ADictionary: string): string;
function GetTagAlias(ADictionary, AKeyWord: string): string;

implementation

uses fgl, fpjson, jsonparser, fphttpclient, opensslsockets, installerCore;

type

  TTagType = (Empty, Release, Fixes, Trunk, ReleaseCandidate);

  TTagInfo = record
    Version: integer;
    Title: string;
    Name: string;
    TagType: TTagType;
  end;

  TTagInfos = specialize TFPGMap<string, TTagInfo>;

const
  FPCProjectID = '28644964';
  FPCTagPrefix = 'release';
  LazarusProjectID = '28419588';
  LazarusTagPrefix = 'lazarus';
  APIUrl = 'https://gitlab.com/api/v4/projects/';
  TagsUrl = '/repository/tags';

var
  LazarusVersions: TTagInfos;
  FpcVersions: TTagInfos;

function ParseTagVersion(const TagPrefix: string; TagJson: TJSONObject; out BranchVersion: TTagInfo): boolean;
var
  SplittedBranchName: TStringArray;
  IndexI, NumValue: integer;
  TagName, TagMessage, PartString: string;
  IsFix, IsTrunk: boolean;
begin
  Result := False;
  BranchVersion.Version := 0;
  BranchVersion.Title := '';
  BranchVersion.Name := '';
  BranchVersion.TagType := Empty;
  TagName := TagJson.Get('name', '');
  TagMessage := LowerCase(TagJson.Get('message', ''));
  SplittedBranchName := TagName.Split('_-.');
  IndexI := Low(SplittedBranchName);
  IsFix := ((TagMessage.Contains('fixes')) and (not TagName.Contains(TagPrefix)));
  IsTrunk := ((TagMessage.Contains('trunk')) or (TagMessage.Contains('main')));

  while (IndexI <= High(SplittedBranchName)) do begin
    PartString := SplittedBranchName[IndexI];

    case (IndexI) of

      0: begin

        if ((PartString = FPCTagPrefix) or (PartString = LazarusTagPrefix)) then begin
          BranchVersion.Name := TagName;
          BranchVersion.TagType := Release;
          Result := True;
        end
        else if ((TagPrefix = FPCTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsFix) then begin
          BranchVersion.Title := 'fixes-' + PartString;
          BranchVersion.Name := 'fixes_' + PartString;
          BranchVersion.Version := (NumValue * 100);
          BranchVersion.TagType := Fixes;
          Result := True;
        end
        else if ((TagPrefix = FPCTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsTrunk) then begin
          BranchVersion.Title := 'trunk';
          BranchVersion.Name := 'trunk'; // TagName;
          BranchVersion.Version := (NumValue * 100);
          BranchVersion.TagType := Trunk;
          Result := True;
        end
        else if ((TagPrefix = LazarusTagPrefix) and (not TryStrToInt(PartString, NumValue)) and IsFix) then begin
          BranchVersion.Title := 'fixes-';
          BranchVersion.Name := 'fixes_';
          BranchVersion.TagType := Fixes;
          Result := True;
        end
        else if ((TagPrefix = LazarusTagPrefix) and (not TryStrToInt(PartString, NumValue)) and IsTrunk) then begin
          BranchVersion.Title := 'trunk';
          BranchVersion.Name := 'trunk'; // TagName;
          BranchVersion.TagType := Trunk;
          Result := True;
        end;

      end;

      1: begin

        if (BranchVersion.TagType = Release) then begin

          if (TryStrToInt(PartString, NumValue)) then begin
            BranchVersion.Title := PartString;
            BranchVersion.Version += (NumValue * 100);
          end;

        end
        else if ((TagPrefix = FPCTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsFix) then begin
          BranchVersion.Title += '.' + PartString;
          BranchVersion.Name += '_' + PartString;
          BranchVersion.Version += (NumValue * 10);
        end
        else if ((TagPrefix = FPCTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsTrunk) then begin
          BranchVersion.Version += (NumValue * 10);
        end
        else if ((TagPrefix = LazarusTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsFix) then begin
          Result := False;
          break;
        end
        else if ((TagPrefix = LazarusTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsTrunk) then begin
          BranchVersion.Version += (NumValue * 100);
        end;

      end;

      2: begin

        if (BranchVersion.TagType = Release) then begin

          if (TryStrToInt(PartString, NumValue)) then begin
            BranchVersion.Title += '.' + PartString;
            BranchVersion.Version += (NumValue * 10);
          end;

        end
        else if ((TagPrefix = FPCTagPrefix) and (TryStrToInt(PartString, NumValue)) and (IsFix or IsTrunk)) then begin
          BranchVersion.Version += NumValue;
        end
        else if ((TagPrefix = LazarusTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsFix) then begin
          BranchVersion.Title += PartString;
          BranchVersion.Name += PartString;
          BranchVersion.Version += (NumValue * 100);
        end
        else if ((TagPrefix = LazarusTagPrefix) and (TryStrToInt(PartString, NumValue)) and IsTrunk) then begin
          BranchVersion.Version += NumValue;
        end;

      end;

      3: begin

        if (BranchVersion.TagType = Release) then begin

          if (TryStrToInt(PartString, NumValue)) then begin
            BranchVersion.Title += '.' + PartString;
            BranchVersion.Version += NumValue;
          end
          else if (LowerCase(PartString).Contains('rc')) then begin
            BranchVersion.Title += PartString;
            BranchVersion.TagType := ReleaseCandidate;
          end
          else begin
            Result := False;
            break;
          end;

        end;

      end;

      4: begin

        if (BranchVersion.TagType = Release) then begin

          if (not TryStrToInt(PartString, NumValue)) then begin
            BranchVersion.Title += '.' + PartString;

            if (LowerCase(PartString).Contains('rc')) then begin
              BranchVersion.TagType := ReleaseCandidate;
            end;

          end;

        end
        else if ((BranchVersion.TagType = ReleaseCandidate) and (TryStrToInt(PartString, NumValue))) then begin
          BranchVersion.Title += PartString;
        end;

      end;

    end;

    Inc(IndexI);
  end;

  if (Result) then begin
    BranchVersion.Title += '.gitlab';
  end;

end;

function GetTagVersions(const ProjectID: string; const TagPrefix: string): TTagInfos;
var
  FetchURL, TagJson: string;
  JsonData: TJSONData;
  TagList: TJSONArray;
  TagObject: TJSONEnum;
  ParsedBranch: TTagInfo;
  IndexI, MaxVersion: integer;
begin
  FetchURL := APIUrl + ProjectID + TagsUrl;
  TagJson := TFPHTTPClient.SimpleGet(FetchURL);
  JsonData := GetJSON(TagJson);

  try
    TagList := JsonData as TJSONArray;
    Result := TTagInfos.Create;

    for TagObject in TagList do begin

      if ParseTagVersion(TagPrefix, TagObject.Value as TJSONObject, ParsedBranch) then begin
        Result.Add(ParsedBranch.Title, ParsedBranch);
      end;

    end;

    MaxVersion := -1;

    for IndexI := 0 to (Result.Count - 1) do begin

      if ((Result.Data[IndexI].TagType = Trunk) and (Result.Data[IndexI].Version > MaxVersion)) then begin
        MaxVersion := Result.Data[IndexI].Version;
        ParsedBranch := Result.Data[IndexI];
      end;

    end;

    for IndexI := (Result.Count - 1) downto 0 do begin

      if ((Result.Data[IndexI].TagType = Trunk) and (Result.Data[IndexI].Version < ParsedBranch.Version)) then begin
        Result.Delete(IndexI);
      end;

    end;

    MaxVersion := -1;

    for IndexI := 0 to (Result.Count - 1) do begin

      if ((Result.Data[IndexI].TagType = Release) and (Result.Data[IndexI].Version > MaxVersion)) then begin
        MaxVersion := Result.Data[IndexI].Version;
        ParsedBranch := Result.Data[IndexI];
      end;

    end;

    if (MaxVersion > -1) then begin
      ParsedBranch.Title := 'stable.gitlab';
      Result.Add('stable.gitlab', ParsedBranch);
    end;

    MaxVersion := -1;

    for IndexI := 0 to (Result.Count - 1) do begin

      if ((Result.Data[IndexI].TagType = Fixes) and (Result.Data[IndexI].Version > MaxVersion)) then begin
        MaxVersion := Result.Data[IndexI].Version;
        ParsedBranch := Result.Data[IndexI];
      end;

    end;

    if (MaxVersion > -1) then begin
      ParsedBranch.Title := 'fixes.gitlab';
      Result.Add('fixes.gitlab', ParsedBranch);
    end;

  finally
    JsonData.Free;
  end;

end;

procedure InitGitLabVersions;
begin
  LazarusVersions := GetTagVersions(LazarusProjectID, LazarusTagPrefix);
  FpcVersions := GetTagVersions(FPCProjectID, FPCTagPrefix);
end;

function GetTagList(ADictionary: string): string;
var
  TagList: TStringList;
  IndexI: integer;
begin

  try
    TagList := TStringList.Create;

    if (ADictionary = FPCTAGLOOKUPMAGIC) then begin

      for IndexI := 0 to (FpcVersions.Count - 1) do begin
        TagList.Add(FpcVersions.Data[IndexI].Title);
      end;

    end
    else if (ADictionary = LAZARUSTAGLOOKUPMAGIC) then begin

      for IndexI := 0 to (LazarusVersions.Count - 1) do begin
        TagList.Add(LazarusVersions.Data[IndexI].Title);
      end;

    end;

    Result := TagList.CommaText;
  finally
    TagList.Free;
  end;

end;

function GetTagAlias(ADictionary, AKeyWord: string): string;
var
  Tag: TTagInfo;
  Index: integer;
  Alias: string;
begin

  if (ADictionary = FPCTAGLOOKUPMAGIC) then begin
    Index := FpcVersions.IndexOf(AKeyWord);

    if (Index >= 0) then begin
      Tag := FpcVersions.Data[Index];

      if ((Tag.TagType = Release) or (Tag.TagType = ReleaseCandidate)) then begin
        Alias := Tag.Name;
      end;

    end;

  end
  else if (ADictionary = FPCBRANCHLOOKUPMAGIC) then begin
    Index := FpcVersions.IndexOf(AKeyWord);

    if (Index >= 0) then begin
      Tag := FpcVersions.Data[Index];

      if ((Tag.TagType = Fixes) or (Tag.TagType = Trunk)) then begin
        Alias := Tag.Name;
      end;

    end;

  end
  else if (ADictionary = LAZARUSTAGLOOKUPMAGIC) then begin
    Index := LazarusVersions.IndexOf(AKeyWord);

    if (Index >= 0) then begin
      Tag := LazarusVersions.Data[Index];

      if ((Tag.TagType = Release) or (Tag.TagType = ReleaseCandidate)) then begin
        Alias := Tag.Name;
      end;

    end;

  end
  else if (ADictionary = LAZARUSBRANCHLOOKUPMAGIC) then begin
    Index := LazarusVersions.IndexOf(AKeyWord);

    if (Index >= 0) then begin
      Tag := LazarusVersions.Data[Index];

      if ((Tag.TagType = Fixes) or (Tag.TagType = Trunk)) then begin
        Alias := Tag.Name;
      end;

    end;

  end;

  Result := Alias;
end;

initialization
  InitGitLabVersions;

finalization
  LazarusVersions.Free;
  FpcVersions.Free;
end.
