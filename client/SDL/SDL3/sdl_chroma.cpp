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

#include "sdl_chroma.hpp"
#include <cmath>
#include <algorithm>

bool SdlChroma::isChromaKeyPixel(uint32_t chromaKeyColor, float chromaKeyTolerance, uint32_t pixel)
{
	uint8_t targetR = (chromaKeyColor >> 16) & 0xFF;
	uint8_t targetG = (chromaKeyColor >> 8) & 0xFF;
	uint8_t targetB = chromaKeyColor & 0xFF;

	uint8_t b = (pixel >> 0) & 0xFF;
	uint8_t g = (pixel >> 8) & 0xFF;
	uint8_t r = (pixel >> 16) & 0xFF;

	float diffR = std::fabs(static_cast<float>(r) - static_cast<float>(targetR));
	float diffG = std::fabs(static_cast<float>(g) - static_cast<float>(targetG));
	float diffB = std::fabs(static_cast<float>(b) - static_cast<float>(targetB));

	float maxDiff = std::fmax(std::fmax(diffR, diffG), diffB);

	return maxDiff <= chromaKeyTolerance;
}

bool SdlChroma::hasChromaKeyMargin(uint32_t chromaKeyColor, float chromaKeyTolerance,
                                  const rdpGdi* gdi, int x, int y, int radius)
{
	uint32_t* buffer =
	    gdi ? reinterpret_cast<uint32_t*>(gdi->primary_buffer) : nullptr;

	if (!gdi || !buffer || radius < 1)
		return false;

	for (int dy = -radius; dy <= radius; dy++)
	{
		for (int dx = -radius; dx <= radius; dx++)
		{
			if ((dx == 0) && (dy == 0))
				continue;

			int nx = x + dx;
			int ny = y + dy;

			if (nx < 0 || nx >= static_cast<int>(gdi->width) || ny < 0 ||
			    ny >= static_cast<int>(gdi->height))
				return false;

			uint32_t pixel = buffer[static_cast<size_t>(ny) * gdi->width + static_cast<size_t>(nx)];
			if (!isChromaKeyPixel(chromaKeyColor, chromaKeyTolerance, pixel))
				return false;
		}
	}

	return true;
}

std::vector<SDL_Rect> SdlChroma::calculateOpaqueRegions(uint32_t chromaKeyColor,
                                                       float chromaKeyTolerance, const rdpGdi* gdi,
                                                       int minRegionSize)
{
	std::vector<SDL_Rect> regions;

	if (!gdi || !gdi->primary_buffer || gdi->width == 0 || gdi->height == 0)
		return regions;

	uint32_t* buffer = reinterpret_cast<uint32_t*>(gdi->primary_buffer);
	std::vector<std::vector<bool>> visited(gdi->height, std::vector<bool>(gdi->width, false));

	for (uint32_t y = 0; y < gdi->height; y++)
	{
		for (uint32_t x = 0; x < gdi->width; x++)
		{
			if (visited[y][x])
				continue;

			uint32_t pixel = buffer[y * gdi->width + x];
			if (isChromaKeyPixel(chromaKeyColor, chromaKeyTolerance, pixel))
			{
				visited[y][x] = true;
				continue;
			}

			int minX = static_cast<int>(x);
			int minY = static_cast<int>(y);
			int maxX = minX;
			int maxY = minY;

			for (uint32_t cy = y; cy < gdi->height; cy++)
			{
				bool foundOpaque = false;
				for (uint32_t cx = (cy == y ? x : 0); cx < gdi->width; cx++)
				{
					if (visited[cy][cx])
						continue;

					uint32_t p = buffer[cy * gdi->width + cx];
					if (!isChromaKeyPixel(chromaKeyColor, chromaKeyTolerance, p))
					{
						if (cx > static_cast<uint32_t>(maxX))
							maxX = static_cast<int>(cx);
						if (cy > static_cast<uint32_t>(maxY))
							maxY = static_cast<int>(cy);
						visited[cy][cx] = true;
						foundOpaque = true;
					}
				}
				if (!foundOpaque && cy > y)
					break;
			}

			int width = maxX - minX + 1;
			int height = maxY - minY + 1;

			if (width >= minRegionSize && height >= minRegionSize)
			{
				regions.push_back(SDL_Rect{minX, minY, width, height});
			}
		}
	}

	return regions;
}
