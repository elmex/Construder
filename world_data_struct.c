typedef struct _ctr_axis_node {
    int coord;
    void *ptr;
} ctr_axis_node;

typedef struct _ctr_axis_array {
   ctr_axis_node *nodes;
   unsigned int len;
   unsigned int alloc;
} ctr_axis_array;


void ctr_axis_array_grow (ctr_axis_array *arr, unsigned int min_size)
{
  if (arr->alloc > min_size)
    return;

  if (arr->alloc == 0)
    {
      arr->alloc = 64;
      arr->nodes = malloc (sizeof (ctr_axis_node) * arr->alloc);
      memset (arr->nodes, 0, sizeof (ctr_axis_node) * arr->alloc);
      arr->len = 0;
      return;
    }

  unsigned int oa = arr->alloc;

  while (arr->alloc < min_size)
    arr->alloc *= 2;

  ctr_axis_node *newnodes = malloc (sizeof (ctr_axis_node) * arr->alloc);
  assert (newnodes);
  memset (newnodes, 0, sizeof (ctr_axis_node) * arr->alloc);
  memcpy (newnodes, arr->nodes, sizeof (ctr_axis_node) * oa);
  free (arr->nodes);
  arr->nodes = newnodes;
}

ctr_axis_array *ctr_axis_array_new ()
{
  ctr_axis_array *na = malloc (sizeof (ctr_axis_array));
  memset (na, 0, sizeof (ctr_axis_array));
  na->len = 0;
  na->alloc = 0;
  ctr_axis_array_grow (na, 1);
  return na;
}

void ctr_axis_array_dump (ctr_axis_array *arr)
{
  int i;
  printf ("alloc: %d\n", arr->alloc);
  for (i = 0; i < arr->len; i++)
    printf ("%d: %d (%p)\n", i, arr->nodes[i].coord, arr->nodes[i].ptr);
}


void ctr_axis_array_insert_at (ctr_axis_array *arr, unsigned int idx, int coord, void *ptr)
{
  if ((arr->len + 1) >= arr->alloc)
    ctr_axis_array_grow (arr, arr->len + 1);

  assert (arr->alloc >= arr->len + 1);

  ctr_axis_node *an = 0;
  if (arr->len > idx)
    {
      unsigned int tail_len = arr->len - idx;

      // checking...
      // idx:   len:
      // 0      1, 2, 10     tl:1, tl:2, tl:10
      // 1      1, 2, 10     tl:?, tl:1, tl:9
      // 5      1, 2, 10     tl:?, tl:?, tl:5
      // 10     1, 2, 10

      memmove (arr->nodes + idx + 1, arr->nodes + idx,
               sizeof (ctr_axis_node) * tail_len);
    }

  an = &(arr->nodes[idx]);

  an->coord = coord;
  an->ptr   = ptr;
  arr->len++;
}

void *ctr_axis_array_remove_at (ctr_axis_array *arr, unsigned int idx)
{
  assert (idx < arr->len);
  void *ptr = arr->nodes[idx].ptr;

  if ((idx + 1) < arr->len)
    {
      unsigned int tail_len = arr->len - (idx + 1);
      memmove (arr->nodes + idx, arr->nodes + idx + 1,
                sizeof (ctr_axis_node) * tail_len);
    }

  arr->len--;
  return ptr;
}

unsigned int ctr_axis_array_find (ctr_axis_array *arr, int coord, ctr_axis_node **node)
{
  *node = 0;
  if (arr->len == 0)
    return 0;

  int min = 0;
  int max = arr->len; // include last free index

  int mid = 0;
  while (min < max)
    {
      mid = min + (max - min) / 2;
      if (mid == arr->len || arr->nodes[mid].coord >= coord)
        max = mid;
      else
        min = mid + 1;
    }

  if (min < arr->len && arr->nodes[min].coord == coord)
    *node = &(arr->nodes[min]);

  return min;
}

void *ctr_axis_get (ctr_axis_array *arr, int coord)
{
  ctr_axis_node *node = 0;
  ctr_axis_array_find (arr, coord, &node);
  return node ? node->ptr : 0;
}

void *ctr_axis_add (ctr_axis_array *arr, int coord, void *ptr)
{
  ctr_axis_node *node = 0;
  unsigned int idx = ctr_axis_array_find (arr, coord, &node);
  if (node)
    {
      void *oldptr = node->ptr;
      node->coord = coord;
      node->ptr   = ptr;
      return oldptr;
    }
  else
    ctr_axis_array_insert_at (arr, idx, coord, ptr);

  return 0;
}

void *ctr_axis_remove (ctr_axis_array *arr, int coord)
{
  ctr_axis_node *node = 0;
  unsigned int idx = ctr_axis_array_find (arr, coord, &node);
  if (node)
    return ctr_axis_array_remove_at (arr, idx);
  return 0;
}
