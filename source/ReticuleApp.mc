import Toybox.Application;

class ReticuleApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new ReticuleView()];
    }
}
