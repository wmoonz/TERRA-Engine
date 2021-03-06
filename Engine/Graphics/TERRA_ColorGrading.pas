{***********************************************************************************************************************
 *
 * TERRA Game Engine
 * ==========================================
 *
 * Copyright (C) 2003, 2014 by S�rgio Flores (relfos@gmail.com)
 *
 ***********************************************************************************************************************
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
 * an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 **********************************************************************************************************************
 * TERRA_ColorTable
 * Implements color ramps/palettes via shaders
 ***********************************************************************************************************************
}
Unit TERRA_ColorGrading;

{$I terra.inc}

Interface
Uses TERRA_Utils, TERRA_Texture, TERRA_Shader, TERRA_Color, TERRA_Image, TERRA_Vector3D;

Const
  ColorTableUniformName = 'color_table_texture';

Type
  ColorTransform = Function (N:Color; Userdata:Pointer):Color; Cdecl;

  Function CreateColorTable(Size:Integer; Transform:ColorTransform = Nil; Userdata:Pointer = Nil):Image;
  Function ColorTableLookUp(ColorTable:Image; Source:Color):Color;
  Procedure ColorTableTransform(Dest, ColorTable:Image);

  Function GetColorTableShaderCode():AnsiString;
  Function ColorTableBind(ColorTableTex:Texture; Slot:Integer):Boolean;

Implementation
Uses TERRA_OS, TERRA_Log;

Function CreateColorTable(Size:Integer; Transform:ColorTransform; Userdata:Pointer):Image;
Var
  Scale:Single;
  R,G,B:Integer;
  Temp:Color;
Begin
  Result := Image.Create(Size * Size, Size);
  Scale := 255/Pred(Size);
  For R:=0 To Pred(Size) Do
    For G:=0 To Pred(Size) Do
      For B:=0 To Pred(Size) Do
      Begin
        Temp := ColorCreate(Byte(Trunc(R*Scale)), Byte(Trunc(G*Scale)), Byte(Trunc(B*Scale)), 255);
        If Assigned(Transform) Then
          Temp := Transform(Temp, Userdata);

        Result.SetPixel(R+B*Size, G, Temp);
      End;
End;

Procedure ColorTableTransform(Dest, ColorTable:Image);
Var
  I,J:Integer;
  P:Color;
Begin
  For J:=0 To Pred(Dest.Height) Do
    For I:=0 To Pred(Dest.Width) Do
    Begin
      P := Dest.GetPixel(I,J);
      P := ColorTableLookUp(ColorTable, P);
      Dest.SetPixel(I, J, P);
    End;
End;

Function ColorTableLookUp(ColorTable:Image; Source:Color):Color;
Var
  R1,G1,B1:Single;
  R2,G2,B2:Single;
  DR,DG,DB:Single;
  Scale:Single;
Begin
  If (ColorTable = Nil) Then
  Begin
    Result := Source;
    Exit;
  End;

  Scale := 1/(255/ColorTable.Height);

  DR := Frac(Source.R * Scale);
  DG := Frac(Source.G * Scale);
  DB := Frac(Source.B * Scale);

  R1 := Trunc(Source.R * Scale);
  G1 := Trunc(Source.G * Scale);
  B1 := Trunc(Source.B * Scale);

  R2 := Round(Source.R * Scale);
  G2 := Round(Source.G * Scale);
  B2 := Round(Source.B * Scale);

  Result := ColorTable.GetPixel(Trunc(R1*(1.0-DR) + R2*DR) + Trunc(B1*(1.0-DB) + B2*DB) * ColorTable.Height, Trunc(G1*(1.0-DG) + G2*DG));
End;

Function ColorTableBind(ColorTableTex:Texture; Slot:Integer):Boolean;
Var
  MyShader:Shader;
  Scale:Single;
  TableWidth:Single;
  Elements:Single;
Begin
  Result := False;

  MyShader := ShaderManager.Instance.ActiveShader;
  If (MyShader = Nil) Then
    Exit;

  If (Not MyShader.HasUniform(ColorTableUniformName)) Then
    Exit;

  If (ColorTableTex = Nil) Or (Not ColorTableTex.IsReady()) Then
  Begin
    If (ColorTableTex<>TextureManager.Instance.DefaultColorTable) Then
      ColorTableBind(TextureManager.Instance.DefaultColorTable, Slot);
    Exit;
  End;

  Elements := ColorTableTex.Height;
  TableWidth := ColorTableTex.Width;

  MyShader.SetUniform(ColorTableUniformName, Slot);
  MyShader.SetUniform('color_table_elements', Elements);
  MyShader.SetUniform('color_table_width', 1 / TableWidth);
  MyShader.SetUniform('color_table_scale', VectorCreate(Elements, 1.0 / Elements, 1.0 / (Elements - 1)));
//  MyShader.SetUniform('color_table_clamp', VectorUniform(Elements-1));

  ColorTableTex.BilinearFilter := True;
  ColorTableTex.Wrap := False;
  ColorTableTex.MipMapped := False;
  ColorTableTex.Bind(Slot);
  Result := True;
End;

Function GetColorTableShaderCode():AnsiString;
Var
  S:AnsiString;
Procedure Line(S2:AnsiString); Begin S := S + S2 + crLf; End;
Begin
  S := '';
	Line('  uniform sampler2D color_table_texture;');
  Line('  uniform highp float color_table_elements;');
  Line('  uniform highp float color_table_width;');
  Line('  uniform mediump vec3 color_table_scale;');

	Line('lowp vec3 ColorTableLookup(highp vec3 color)	{');

  Line('  color *= color_table_scale.x;');

  Line('  mediump float delta = fract(color.b);');

  Line('  highp float red = floor(color.r);');
  Line('  highp float green = floor(color.g);');
  Line('  highp float blue1 = floor(color.b);');

//  calculate first offset
  Line('  highp float px = (color_table_elements * blue1 + red + 0.5) * color_table_width;');
  Line('  highp float py = green * color_table_scale.z;');

  Line('  highp float minpx = (color_table_elements * blue1 + 0.5) * color_table_width;');
  Line('  highp float maxpx = (color_table_elements * (blue1 + 1.0) - 0.5) * color_table_width;');

  Line('  px = min(px, maxpx);');
  Line('  px = max(px, minpx);');

  // loop up first color
  Line('  mediump vec2 ofs = vec2(px, py);');
  Line('  mediump vec3 temp1 = texture2D(color_table_texture, ofs).rgb;');

//  calculate second offset
  Line('  px += color_table_scale.y;');
  Line('  px = min(px, 1.0);');

  // loop up second color
  Line('  ofs = vec2(px, py);');
  Line('  mediump vec3 temp2 = texture2D(color_table_texture, ofs).rgb;');

  // interpolate
  Line('return mix(temp1, temp2, delta);	}');

  Result := S;
End;

End.