typedef struct _ctr_queue {
    void         *data;
    void         *data_end;
    unsigned int  item_size;
    unsigned int  alloc_items;
    void *start, *end;
} ctr_queue;

void ctr_queue_clear (ctr_queue *q)
{
  q->start = q->data;
  q->end   = q->data;
}

ctr_queue *ctr_queue_new (unsigned int item_size, unsigned int alloc_items)
{
  ctr_queue *q = malloc (sizeof (ctr_queue));

  assert (alloc_items > 1);

  q->data     = malloc (item_size * alloc_items);
  q->data_end = q->data + (item_size * alloc_items);

  q->item_size   = item_size;
  q->alloc_items = alloc_items;

  ctr_queue_clear (q);

  return q;
}

void ctr_queue_free (ctr_queue *q)
{
  free (q->data);
  free (q);
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

int ctr_queue_dequeue (ctr_queue *q, void **item)
{
  if (q->start == q->end)
    return 0;

  *item = q->start;

  q->start += q->item_size;
  if (q->start == q->data_end) // wrap around
    q->start = q->data;

  return 1;
}
