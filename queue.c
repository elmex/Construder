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
/* This file holds a primitive queue implementation.
 * Mainly used by the light algorithm at the moment of this writing.
 */
typedef struct _ctr_queue {
    unsigned char *data;
    unsigned char *data_end;
    unsigned int  item_size;
    unsigned int  alloc_items;
    unsigned char *start, *end;
    unsigned char *freeze_start, *freeze_end;
} ctr_queue;

void ctr_queue_clear (ctr_queue *q)
{
  q->start = q->data;
  q->end   = q->data;
}

ctr_queue *ctr_queue_new (unsigned int item_size, unsigned int alloc_items)
{
  ctr_queue *q = safemalloc (sizeof (ctr_queue));
  q->freeze_start = 0;
  q->freeze_end   = 0;
  q->data = 0;
  q->data_end = 0;
  q->start = 0;
  q->end = 0;

  assert (alloc_items > 1);

  q->data     = safemalloc (item_size * alloc_items);
  q->data_end = q->data + (item_size * alloc_items);

  q->item_size   = item_size;
  q->alloc_items = alloc_items;

  ctr_queue_clear (q);

  return q;
}

void ctr_queue_free (ctr_queue *q)
{
  safefree (q->data);
  safefree (q);
}

void ctr_queue_enqueue (ctr_queue *q, void *item)
{
  memcpy (q->end, item, q->item_size);

  q->end += q->item_size;

  if (q->end == q->data_end) // wrap pointer
    {
      q->end = q->data;
      assert (q->start != q->end);
    }
}

/* This function stores the state of the queue, so
 * we can quickly restore the queue using the queue_thaw method.
 */
void ctr_queue_freeze (ctr_queue *q)
{
  q->freeze_start = q->start;
  q->freeze_end   = q->end;
}

void ctr_queue_thaw (ctr_queue *q)
{
  q->start = q->freeze_start;
  q->end   = q->freeze_end;
}

void *ctr_queue_dequeue (ctr_queue *q)
{
  if (q->start == q->end)
    return 0;

  void *ptr = q->start;

  q->start += q->item_size;
  if (q->start == q->data_end) // wrap around
    q->start = q->data;

  return ptr;
}
