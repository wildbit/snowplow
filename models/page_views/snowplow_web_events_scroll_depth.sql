
{{
    config(
        materialized='table',
        sort='page_view_id',
        dist='page_view_id'
    )
}}

{{ "{% " }} set this_schema = "{{ this.schema }}" {{ " %}" }}
{{ "{% " }} set this_name = "{{ this.name }}" {{ " %}" }}

with events as (

    {{ snowplow.select_new_events('snowplow_base_events', this.schema, this.name, "max_tstamp") }}

),

web_page_context as (

    select * from {{ ref('snowplow_web_page_context') }}

),

prep as (

    select

        wp.page_view_id,

        max(ev.collector_tstamp) as max_tstamp,

        max(ev.doc_width) as doc_width,
        max(ev.doc_height) as doc_height,

        max(ev.br_viewwidth) as br_viewwidth,
        max(ev.br_viewheight) as br_viewheight,

        least(greatest(min(nvl(ev.pp_xoffset_min, 0)), 0), max(ev.doc_width)) as hmin,
        least(greatest(max(nvl(ev.pp_xoffset_max, 0)), 0), max(ev.doc_width)) as hmax,

        least(greatest(min(nvl(ev.pp_yoffset_min, 0)), 0), max(ev.doc_height)) as vmin,
        least(greatest(max(nvl(ev.pp_yoffset_max, 0)), 0), max(ev.doc_height)) as vmax

    from events as ev
        inner join web_page_context as wp on ev.event_id = wp.root_id

    where ev.event_name in ('page_view', 'page_ping')
      and ev.doc_height > 0
      and ev.doc_width > 0

    group by 1

),

relative as (

    select

        page_view_id,
        max_tstamp,

        doc_width,
        doc_height,
        br_viewwidth,
        br_viewheight,

        hmin,
        hmax,
        vmin,
        vmax,

        round(100*(greatest(hmin, 0)/doc_width::float)) as relative_hmin,
        round(100*(least(hmax + br_viewwidth, doc_width)/doc_width::float)) as relative_hmax,
        round(100*(greatest(vmin, 0)/doc_height::float)) as relative_vmin,
        round(100*(least(vmax + br_viewheight, doc_height)/doc_height::float)) as relative_vmax

    from prep

),

{% raw %}

    {% if already_exists(this_schema, this_name) %}

relevant_existing as (

    select
        page_view_id,
        max_tstamp,
        doc_width,
        doc_height,
        br_viewwidth,
        br_viewheight,
        hmin,
        hmax,
        vmin,
        vmax,
        relative_hmin,
        relative_hmax,
        relative_vmin,
        relative_vmax
    from "{{ this_schema }}"."{{ this_name }}"
),

unioned as (

    select
        page_view_id,
        max_tstamp,
        doc_width,
        doc_height,
        br_viewwidth,
        br_viewheight,
        hmin,
        hmax,
        vmin,
        vmax,
        relative_hmin,
        relative_hmax,
        relative_vmin,
        relative_vmax
    from relative

    union all

    select
        page_view_id,
        max_tstamp,
        doc_width,
        doc_height,
        br_viewwidth,
        br_viewheight,
        hmin,
        hmax,
        vmin,
        vmax,
        relative_hmin,
        relative_hmax,
        relative_vmin,
        relative_vmax
    from relevant_existing

),


merged as (

    select
        page_view_id,
        max(max_tstamp) as max_tstamp,
        max(doc_width) as doc_width,
        max(doc_height) as doc_height,
        max(br_viewwidth) as br_viewwidth,
        max(br_viewheight) as br_viewheight,
        max(hmin) as hmin,
        max(hmax) as hmax,
        max(vmin) as vmin,
        max(vmax) as vmax,
        max(relative_hmin) as relative_hmin,
        max(relative_hmax) as relative_hmax,
        max(relative_vmin) as relative_vmin,
        max(relative_vmax) as relative_vmax

    from unioned
    group by 1


)

{% else %}

merged as (

    select * from relative

)

{% endif %}


{% endraw %}


select * from merged
