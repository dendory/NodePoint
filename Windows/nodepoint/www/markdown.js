function insertAtCursor(startvalue, endvalue, text)
{
    field = document.getElementById('markdown');
    if(field.selectionStart || field.selectionStart == '0') 
    {
        var startPos = field.selectionStart;
        var endPos = field.selectionEnd;
        if(startPos == endPos)
        {
            field.value = field.value.substring(0, startPos) + startvalue + text + endvalue + field.value.substring(endPos, field.value.length);
            field.focus();
            field.setSelectionRange(startPos + startvalue.length , endPos + startvalue.length + text.length)
        }
        else
        {
            field.value = field.value.substring(0, startPos) + startvalue + field.value.substring(startPos, endPos) + endvalue + field.value.substring(endPos, field.value.length);
            field.focus();
            field.setSelectionRange(startPos + startvalue.length , endPos + startvalue.length)
        }
    }
    else
    {
        field.value += value;
        field.focus();
    }
}

function md_bold()
{
    insertAtCursor('**', '**', '');
}

function md_italic()
{
    insertAtCursor('*', '*', '');
}

function md_list()
{
    insertAtCursor('* ', '', '');
}

function md_code()
{
    insertAtCursor('`', '`', '');
}

function md_header()
{
    insertAtCursor('### ', '', '');
}

function md_image()
{
    var text = prompt("Image URL", "/path/to/img.jpg");
    if(text !== null) { insertAtCursor('![', '](' + text + ')', 'Alt text'); }
}

function md_link()
{
    var text = prompt("Link URL", "http://")
    if(text !== null) { insertAtCursor('[', '](' + text + ')', 'Link description'); }
}

