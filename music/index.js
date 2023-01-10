var dropPlaceholder = true;
var url = "$URL_PLACEHOLDER"

function uploadFile(file) {
    let el = document.createElement("tr");
    let nameel = document.createElement("td");
    nameel.className = "dropped-file-name";
    nameel.innerText = file.name;
    el.appendChild(nameel);
    let linkel = document.createElement("td");
    linkel.className = "dropped-file-link";
    let linka = document.createElement("a");
    linka.href = "";
    linka.innerText = "Uploading...";
    linkel.appendChild(linka);
    el.appendChild(linkel);
    let percentel = document.createElement("td");
    percentel.className = "dropped-file-percent";
    percentel.innerText = "0%";
    el.appendChild(percentel);
    document.getElementById("dropped-files").appendChild(el);
    fetch(url + "/upload", {
        method: "POST",
        headers: {"Content-Type": "application/octet-stream"},
        body: file
    }).then(response => {
        if (!response.ok) {
            percentel.innerText = "Failed";
            linka.remove();
            response.json().then(error => linkel.innerText = error.error);
        } else {
            response.text().then(id => {
                percentel.innerText = "100%";
                linka.href = url + "/content/" + id + ".dfpwm";
                linka.innerText = url + "/content/" + id + ".dfpwm";
            });
        }
    }).catch(error => {
        percentel.innerText = "Failed";
        linka.remove();
        linkel.innerText = error;
    });
}

function dropFile(event) {
    event.preventDefault();
    dragEnd(event);
    if (dropPlaceholder) {
        document.getElementById("dropped-files-outer").innerHTML = "";
        let el = document.createElement("table");
        el.id = "dropped-files";
        document.getElementById("dropped-files-outer").appendChild(el);
        dropPlaceholder = false;
    }
    if (event.dataTransfer.items) {
        // Use DataTransferItemList interface to access the file(s)
        for (var i = 0; i < event.dataTransfer.items.length; i++) {
            // If dropped items aren't files, reject them
            if (event.dataTransfer.items[i].kind === 'file') {
                var file = event.dataTransfer.items[i].getAsFile();
                console.log('... file[' + i + '].name = ' + file.name);
                uploadFile(file);
            }
        }
    } else {
        // Use DataTransfer interface to access the file(s)
        for (var i = 0; i < event.dataTransfer.files.length; i++) {
            console.log('... file[' + i + '].name = ' + event.dataTransfer.files[i].name);
            uploadFile(event.dataTransfer.files[i]);
        }
    }
}

function dropFileButton(event) {
    event.preventDefault();
    dragEnd(event);
    if (dropPlaceholder) {
        document.getElementById("dropped-files-outer").innerHTML = "";
        let el = document.createElement("table");
        el.id = "dropped-files";
        document.getElementById("dropped-files-outer").appendChild(el);
        dropPlaceholder = false;
    }
    let dataTransfer = document.getElementById("drop-files-button");
    for (var i = 0; i < dataTransfer.files.length; i++) {
        console.log('... file[' + i + '].name = ' + dataTransfer.files[i].name);
        uploadFile(dataTransfer.files[i]);
    }
    dataTransfer.value = "";
}

function dragOver(event) {
    event.preventDefault();
    document.getElementById("dropped-files-outer").style.borderColor = "#00aaff"
}

function dragEnd(event) {
    document.getElementById("dropped-files-outer").style.borderColor = "#999999"
}