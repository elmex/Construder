/*
 * Games::Construder - A 3D Game written in Perl with an infinite and modifiable world.
 * Copyright (C) 2011  Robin Redeker
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
/* This file holds the light algorithm. The light is basically done
 * by propagating the light from a light source or other bright block
 * to it's neighbors.
 *
 * It's more or less a simple cellular automaton. The light level of a
 * block is computed from the maximum of the surrounding cells.
 *
 * But the algorithm does not recompute the whole volume this way, but
 * tries to find out the affected area using a flood fill before starting
 * the fix point iteration of computing the light of the cells within that area.
 */

// Utility function to get the maximum light level from the neighbors.
unsigned char ctr_world_query_get_max_light_of_neighbours (x, y, z)
{
  ctr_cell *above = ctr_world_query_cell_at (x, y + 1, z, 0);
  ctr_cell *below = ctr_world_query_cell_at (x, y - 1, z, 0);
  ctr_cell *left  = ctr_world_query_cell_at (x - 1, y, z, 0);
  ctr_cell *right = ctr_world_query_cell_at (x + 1, y, z, 0);
  ctr_cell *front = ctr_world_query_cell_at (x, y, z - 1, 0);
  ctr_cell *back  = ctr_world_query_cell_at (x, y, z + 1, 0);
  unsigned char l = 0;
  if (above && above->light > l) l = above->light;
  if (below && below->light > l) l = below->light;
  if (left  && left->light  > l) l = left->light;
  if (right && right->light > l) l = right->light;
  if (front && front->light > l) l = front->light;
  if (back  && back->light  > l) l = back->light;
  return l;
}

// (Re)flows the light within a query context at the position x,y,z.
void ctr_world_query_reflow_light (int x, int y, int z)
{
  int query_w = QUERY_CONTEXT.x_w * CHUNK_SIZE;

  ctr_world_light_upd_start ();

  ctr_cell *cur = ctr_world_query_cell_at (x, y, z, 0);
  if (!cur)
    return;

  /* First part of this function tries to find out what kind of
   * light change should be recomputed.
   */

  unsigned char l = ctr_world_query_get_max_light_of_neighbours (x, y, z);

  if (ctr_world_cell_transparent (cur)) // a transparent cell has changed
    {
      if (l > 0) l--;
#if DEBUG_LIGHT
      printf ("transparent cell at %d,%d,%d has light %d, neighbors say: %d\n", x, y, z, (int) cur->light, (int) l);
#endif
      if (cur->light < l)
        {
          ctr_world_light_enqueue (x, y, z, l);
        }
      else if (cur->light > l) // we are brighter then the neighbors
        {
          ctr_world_light_enqueue (x, y, z, cur->light);
        }
      else // cur->light == l
        {
          // we are transparent and have the light we should have
          // so we don't need to change anything.
          // XXX: BUT: still force update :)
          ctr_world_query_cell_at (x, y, z, 1);
          return; // => no change, so no change for anyone else
        }
    }
  else // oh, a (light) blocking cell has been set!
    {
      ctr_cell *cur = ctr_world_query_cell_at (x, y, z, 1);
      if (!cur)
        return;

      if (cur->type == 41) // was a light: light it!
        cur->light = 8;
      else if (cur->type == 35) // was a light: light it!
        cur->light = 12;
      else if (cur->type == 40) // was a light: light it!
        cur->light = 15;
      else // oh boy, we will become darker, we are a intransparent block!
        cur->light = 0; // we are blocking light, so we are dark

      // if we are brighter than our neighbours, set our
      // light value are update radius
      if (cur->light > l)
        l = cur->light;
      ctr_world_light_enqueue_neighbours (x, y, z, l);
    }

  /* The following loop tries to find the affected area by flood filling it.
   * While doing that it will compute the queue used in the next loops.
   */
  unsigned char upd_radius = 0;
  while (ctr_world_light_dequeue (&x, &y, &z, &upd_radius))
    {
      // leave a margin, so we can reflow light from the outside...
      if (x <= 0 || y <= 0 || z <= 0
          || x >= (query_w - 1)
          || y >= (query_w - 1)
          || z >= (query_w - 1))
        continue;

      cur = ctr_world_query_cell_at (x, y, z, 0);
      if (!cur || !ctr_world_cell_transparent (cur) || cur->light == 255)
        continue; // ignore blocks that can't be lit or were already visited

      cur = ctr_world_query_cell_at (x, y, z, 1);
      assert (cur);

      cur->light = 255; // insert "visited" marker
      ctr_world_light_select_queue (1);
      ctr_world_light_enqueue (x, y, z, 1);
      ctr_world_light_select_queue (0);
      if (upd_radius > 0)
        ctr_world_light_enqueue_neighbours (x, y, z, upd_radius - 1);
    }

  /* Next loop clears all 255-values that were used to mark the
   * already visited cells.
   */
  ctr_world_light_select_queue (1);
  ctr_world_light_freeze_queue ();

  while (ctr_world_light_dequeue (&x, &y, &z, &upd_radius))
    {
      cur = ctr_world_query_cell_at (x, y, z, 1);
      if (!cur)
        continue;
      cur->light = 0;
    }

  /* Now we iterate over the working set in the queue and
   * compute the light from the neighbors.
   */
  int change = 1;
  int pass = 0;
  while (change)
    {
      change = 0;
      pass++;
#if DEBUG_LIGHT
      printf ("START RELIGHT PASS %d\n", pass);
#endif
      ctr_world_light_thaw_queue ();
      // recompute light for every cell in the queue
      while (ctr_world_light_dequeue (&x, &y, &z, &upd_radius))
        {
          cur = ctr_world_query_cell_at (x, y, z, 0);
          if (!cur)
            continue;

          unsigned char l = ctr_world_query_get_max_light_of_neighbours (x, y, z);
          if (l > 0) l--;
#if DEBUG_LIGHT
          printf ("[%d] relight at %d,%d,%d, me: %d, cur neigh: %d\n", pass, x, y, z, cur->light, l);
#endif
          // if the current cell is too dark, relight it
          if (cur->light < l)
            {
              cur = ctr_world_query_cell_at (x, y, z, 1);
              assert (cur);

              cur->light = l;
              change = 1;
            }
        }
    }
}
