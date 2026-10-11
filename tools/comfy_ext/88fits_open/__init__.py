"""88fits_open: a ComfyUI web extension (no nodes) that opens a saved workflow from the page's URL.

    http://<server>:8188/?open=workflows%2F88fits%2Fgoblin_GOB-E%2F01_goblin_e_front.json

The Level Editor saves every workflow an art job runs into the server's user data (`workflows/88fits/<job folder>/`,
the page's Workflows sidebar) and links each one on the job card; the stock frontend (1.48) knows only `?template=`
and `?share=` links, so this extension reads `?open=<userdata path>` and loads that file (js/open_workflow.js).

Installed by `python tools/comfy.py --install-ext` (scp into ~/ai/ComfyUI/custom_nodes/88fits_open, then a restart under
the ComfyUI lock). The source of truth is the copy in the repo: tools/comfy_ext/88fits_open/.
"""

NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}
WEB_DIRECTORY = "./js"

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
