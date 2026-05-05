/**
 * FreeRDP: A Remote Desktop Protocol Implementation
 * SDL Client chromakey support
 *
 * Copyright 2026 Ben Reaves
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <vector>
#include <SDL3/SDL.h>
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>

class SdlChroma
{
  public:
	[[nodiscard]] static bool isChromaKeyPixel(uint32_t chromaKeyColor, float chromaKeyTolerance,
	                                           uint32_t pixel);

	[[nodiscard]] static bool hasChromaKeyMargin(uint32_t chromaKeyColor, float chromaKeyTolerance,
	                                             const rdpGdi* gdi, int x, int y, int radius);

	[[nodiscard]] static std::vector<SDL_Rect> calculateOpaqueRegions(
	    uint32_t chromaKeyColor, float chromaKeyTolerance, const rdpGdi* gdi, int minRegionSize = 16);
};
