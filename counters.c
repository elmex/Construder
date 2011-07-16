typedef struct _ctr_prof_counters {
    int chunk_changes;
    int active_cell_changes;
    int allocated_axises;
    int allocated_axises_size;
    int noise_cnt;
    int noise_size;
    int dyn_buf_cnt;
    int dyn_buf_size;
    int geom_cnt;
    int allocated_chunks;
} ctr_prof_counters;

static ctr_prof_counters ctr_prof_cnt;

void ctr_prof_init ()
{
  memset (&ctr_prof_cnt, 0, sizeof (ctr_prof_counters));
}
