// assets/js/hooks/image_inspector_hook.js
// Cropper.js を使用した画像クロップと Nudge コントロール
import Cropper from 'cropperjs';
import 'cropperjs/dist/cropper.css';

const ImageInspectorHook = {
  mounted() {
    const image = this.el.querySelector('#inspect-target');
    if (!image) return;

    // 画像が読み込まれてから Cropper を初期化
    const initCropper = () => {
      this.cropper = new Cropper(image, {
        viewMode: 1,
        autoCropArea: 0.5,
        responsive: true,
        guides: true,
        background: true,
        modal: true,
      });
    };

    if (image.complete) {
      initCropper();
    } else {
      image.addEventListener('load', initCropper);
    }

    // LiveView からの Nudge イベントを処理
    this.handleEvent("nudge_crop", ({ direction, amount }) => {
      if (!this.cropper) return;
      const data = this.cropper.getData();
      switch(direction) {
        case "up":    this.cropper.setData({ y: data.y - amount }); break;
        case "down":  this.cropper.setData({ y: data.y + amount }); break;
        case "left":  this.cropper.setData({ x: data.x - amount }); break;
        case "right": this.cropper.setData({ x: data.x + amount }); break;
      }
      // Nudge 後もクロップデータを送信
      this.pushEvent("update_crop_data", this.cropper.getData(true));
    });

    // クロップ操作完了時にデータを LiveView に送信
    this.el.addEventListener('cropend', () => {
      if (!this.cropper) return;
      this.pushEvent("update_crop_data", this.cropper.getData(true));
    });
  },

  destroyed() {
    if (this.cropper) {
      this.cropper.destroy();
    }
  }
};

export default ImageInspectorHook;
